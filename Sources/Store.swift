import AppKit
import SwiftUI
import Security
import LocalAuthentication
import UniformTypeIdentifiers

enum KeyVault {
    private static let service = "local.bytecoder.cmdetranslate.model-api"
    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
    static func contains(_ account: String) -> Bool {
        var q = query(account); q[kSecReturnAttributes as String] = true
        let context = LAContext(); context.interactionNotAllowed = true
        q[kSecUseAuthenticationContext as String] = context
        return SecItemCopyMatching(q as CFDictionary, nil) == errSecSuccess
    }
    static func read(_ account: String) throws -> String {
        var q = query(account); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
            throw AppError.message("无法读取钥匙串中的 API Key（\(status)），请重新保存。")
        }
        return value
    }
    static func save(_ key: String, account: String) throws {
        let q = query(account)
        let data = Data(key.utf8)
        var status = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = q
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw AppError.message("保存 API Key 到钥匙串失败（\(status)）。") }
    }
}

@MainActor
final class AppStore: ObservableObject {
    @Published var tab = "translate"
    @Published var input = ""
    @Published var output = ""
    @Published var target = "auto"
    @Published var direction = ""
    @Published var busy = false
    @Published var translationError = ""
    @Published var matched: [Term] = []
    @Published private(set) var terms: [Term] = []
    @Published private(set) var config = ModelConfig()
    @Published var notice = ""
    @Published var importPreview: [Term]? = nil
    @Published var hotkeyStatus = "正在注册 ⌘E…"
    @Published var accessibilityGranted = AXIsProcessTrusted()
    @Published var lastAction = "等待翻译"
    @Published var canUndo = false
    private var undoTerms: [Term]?
    private var operation: Task<Void, Never>?
    private var generation = UUID()
    private let directory: URL
    private var storageReadable = true

    init() {
        directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("CmdETranslate", isDirectory: true)
        do {
            let decoder = JSONDecoder()
            let configURL = directory.appendingPathComponent("model.json")
            let glossaryURL = directory.appendingPathComponent("glossary.json")
            if FileManager.default.fileExists(atPath: configURL.path) { config = try decoder.decode(ModelConfig.self, from: Data(contentsOf: configURL)) }
            if FileManager.default.fileExists(atPath: glossaryURL.path) { terms = try Glossary.validate(decoder.decode([Term].self, from: Data(contentsOf: glossaryURL))) }
        } catch {
            storageReadable = false
            notice = "读取本地配置失败，原文件已保留。请检查 \(directory.path)；未覆盖任何内容。"
        }
    }

    func refreshPermissions() { accessibilityGranted = AXIsProcessTrusted() }
    var ready: Bool { (try? config.validate()) != nil && (config.isLocal || KeyVault.contains(config.credentialAccount)) }
    func saveConfig(_ value: ModelConfig, newKey: String) throws {
        try value.validate()
        guard storageReadable else { throw AppError.message("本地配置无法读取，请先恢复配置文件。") }
        let key = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty { try KeyVault.save(key, account: value.credentialAccount) }
        guard value.isLocal || KeyVault.contains(value.credentialAccount) else { throw AppError.message("请填写这个接口对应的 API Key。") }
        try persist(value, filename: "model.json")
        config = value
    }
    private func persist<T: Encodable>(_ value: T, filename: String) throws {
        guard storageReadable else { throw AppError.message("本地数据读取失败，为避免覆盖原文件，暂不能保存。") }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let url = directory.appendingPathComponent(filename)
        try encoder.encode(value).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    func changeTerms(_ proposed: [Term]) throws {
        let validated = try Glossary.validate(proposed)
        try persist(validated, filename: "glossary.json")
        undoTerms = terms; canUndo = true; terms = validated
    }
    func saveTerm(_ term: Term) throws {
        guard !terms.contains(where: { $0.id != term.id && $0.normalizedKey == term.normalizedKey }) else { throw AppError.message("英文词条已存在，请编辑已有词条。") }
        var next = terms
        if let i = next.firstIndex(where: { $0.id == term.id }) { next[i] = term } else { next.append(term) }
        try changeTerms(next)
    }
    func undo() {
        guard let undoTerms else { return }
        do {
            try persist(undoTerms, filename: "glossary.json"); terms = undoTerms
            self.undoTerms = nil; canUndo = false; notice = "已撤销上次词库修改。"
        } catch { notice = error.localizedDescription }
    }
    func importFile() {
        let panel = NSOpenPanel()
        panel.title = "导入专业词库"
        panel.allowedContentTypes = [.commaSeparatedText, .tabSeparatedText, .json, .plainText]
        panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { importPreview = try Glossary.parse(Data(contentsOf: url), extension: url.pathExtension) }
        catch { notice = error.localizedDescription }
    }
    func applyImport() {
        guard let importPreview else { return }
        let result = Glossary.merge(importPreview, into: terms)
        do {
            try changeTerms(result.terms); self.importPreview = nil
            notice = "导入完成：新增 \(result.added) 条，更新 \(result.updated) 条。"
        } catch { notice = error.localizedDescription }
    }
    func exportFile(template: Bool = false) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = template ? "专业词库模板.csv" : "专业词库.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let entries = template ? [Term(english: "chargeback", chinese: "拒付", note: "支付场景"), Term(english: "returnless refund", chinese: "免退货退款", note: "售后场景")] : terms
        do { try Glossary.csv(entries).write(to: url, atomically: true, encoding: .utf8); notice = "已保存 \(url.lastPathComponent)。" }
        catch { notice = error.localizedDescription }
    }
    func cancel() { generation = UUID(); operation?.cancel(); operation = nil; busy = false }
    func failSelection(_ message: String) {
        cancel(); input = ""; output = ""; matched = []; direction = ""; translationError = message; lastAction = "取词未完成"
    }
    func translate(_ text: String? = nil) {
        cancel()
        if let text { input = text }
        output = ""; translationError = ""; matched = []
        do {
            let plan = try TranslationPlan.make(text: input, target: target, glossary: terms)
            matched = plan.terms; direction = plan.direction
            try config.validate()
            let key = try KeyVault.read(config.credentialAccount)
            _ = try ModelClient.request(config: config, key: key, plan: plan)
            busy = true; lastAction = "正在请求模型"
            let id = generation, snapshot = config
            operation = Task { [weak self] in
                do {
                    let result = try await ModelClient.translate(config: snapshot, key: key, plan: plan)
                    guard !Task.isCancelled, let self, self.generation == id else { return }
                    self.output = result; self.busy = false; self.lastAction = "翻译完成"
                } catch {
                    guard !Task.isCancelled, let self, self.generation == id else { return }
                    self.busy = false; self.lastAction = "翻译未完成"
                    if let e = error as? URLError {
                        self.translationError = e.code == .timedOut ? "模型请求超时，请稍后重试或换一个速度更快的模型。" : "无法连接模型服务，请检查网络和接口地址。"
                    } else { self.translationError = error.localizedDescription }
                }
            }
        } catch { translationError = error.localizedDescription; lastAction = "需要检查输入或设置" }
    }
    func copyResult() {
        guard !output.isEmpty else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(output, forType: .string)
    }
}
