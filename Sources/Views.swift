import AppKit
import SwiftUI

@MainActor
struct RootView: View {
    @ObservedObject var store: AppStore
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "character.bubble.fill").font(.system(size: 30)).foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text("CmdETranslate").font(.title2.bold())
                    Text("大模型翻译 · 你的专业词库").foregroundStyle(.secondary).font(.callout)
                }
                Spacer()
                Text("选中文字  ⌘ E").font(.callout.monospaced()).padding(9).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }.padding(22)
            TabView(selection: $store.tab) {
                TranslationView(store: store).tabItem { Label("翻译", systemImage: "character.bubble") }.tag("translate")
                GlossaryView(store: store).tabItem { Label("专业词库", systemImage: "books.vertical") }.tag("glossary")
                SettingsView(store: store).tabItem { Label("模型设置", systemImage: "slider.horizontal.3") }.tag("settings")
            }.padding(.horizontal, 16).padding(.bottom, 14)
            Divider()
            HStack {
                Circle().fill(store.hotkeyStatus == "⌘E 已就绪" ? Color.green : Color.orange).frame(width: 7, height: 7)
                Text(store.hotkeyStatus)
                Spacer()
                Text("词库 \(store.terms.filter(\.enabled).count) 条启用")
                Text("·")
                Text(store.accessibilityGranted ? "取词权限已开启" : "取词权限待开启")
            }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 22).padding(.vertical, 11)
        }.frame(minWidth: 740, minHeight: 620)
        .alert("提示", isPresented: Binding(get: { !store.notice.isEmpty }, set: { if !$0 { store.notice = "" } })) {
            Button("好") { store.notice = "" }
        } message: { Text(store.notice) }
    }
}

@MainActor
struct TranslationView: View {
    @ObservedObject var store: AppStore
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("原文").font(.headline)
                Spacer()
                Picker("翻译方向", selection: $store.target) {
                    Text("自动中英互译").tag("auto")
                    Text("翻译成中文").tag("zh-Hans")
                    Text("翻译成英文").tag("en")
                }.frame(width: 245)
            }
            ZStack(alignment: .topLeading) {
                TextEditor(text: $store.input).font(.system(size: 14)).scrollContentBackground(.hidden).padding(7)
                    .accessibilityLabel("待翻译原文")
                if store.input.isEmpty { Text("粘贴文字，或在其他应用选中文字后按 ⌘E").foregroundStyle(.tertiary).padding(13).allowsHitTesting(false) }
            }.frame(minHeight: 112, maxHeight: 180).background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
            HStack {
                Text("\(store.input.count) / 12,000 字").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if store.busy { Button("取消") { store.cancel() } }
                Button(store.busy ? "翻译中…" : "使用模型翻译") { store.translate() }
                    .buttonStyle(.borderedProminent).disabled(store.busy || store.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
            }
            Divider()
            ResultView(store: store)
            if !store.ready {
                HStack {
                    Image(systemName: "slider.horizontal.3").foregroundStyle(.blue)
                    Text("先配置模型接口和 API Key，即可开始翻译。").font(.callout)
                    Spacer()
                    Button("配置模型") { store.tab = "settings" }
                }.padding(12).background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
        }.padding(18)
    }
}

@MainActor
struct ResultView: View {
    @ObservedObject var store: AppStore
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(store.direction.isEmpty ? "译文" : store.direction).font(.headline)
                Spacer()
                if !store.output.isEmpty { Button { store.copyResult() } label: { Label("复制", systemImage: "doc.on.doc") } }
            }
            if store.busy {
                HStack { ProgressView().controlSize(.small); Text("模型正在翻译…").foregroundStyle(.secondary) }.padding(.top, 8)
            } else if !store.translationError.isEmpty {
                Label(store.translationError, systemImage: "exclamationmark.circle").foregroundStyle(.orange).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            } else if store.output.isEmpty {
                Text("译文会显示在这里。").foregroundStyle(.tertiary)
            }
            ScrollView {
                Text(store.output).font(.system(size: 16)).lineSpacing(5).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxWidth: .infinity, minHeight: 70, maxHeight: .infinity)
            if !store.matched.isEmpty {
                Text("已参考 \(store.matched.count) 条术语：" + store.matched.prefix(5).map { "\($0.english) → \($0.chinese)" }.joined(separator: "；") + (store.matched.count > 5 ? "…" : ""))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(3).textSelection(.enabled)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

@MainActor
struct FloatingResultView: View {
    @ObservedObject var store: AppStore
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if store.busy {
                    ProgressView().controlSize(.small).padding(4)
                } else {
                    ScrollView {
                        Text(store.translationError.isEmpty ? (store.output.isEmpty ? "暂无译文" : store.output) : store.translationError)
                            .font(.system(size: 16)).lineSpacing(4).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }.frame(maxWidth: .infinity)
            VStack(spacing: 12) {
                Button { AppDelegate.shared?.hideResult() } label: { Image(systemName: "xmark") }
                    .help("关闭（Esc）").accessibilityLabel("关闭译文")
                if !store.output.isEmpty && !store.busy {
                    Button { store.copyResult() } label: { Image(systemName: "doc.on.doc") }
                        .help("复制").accessibilityLabel("复制译文")
                }
            }.buttonStyle(.plain).foregroundStyle(.secondary)
        }.padding(16).frame(width: 360, height: compactHeight)
            .onAppear { AppDelegate.shared?.resizeResult(height: compactHeight) }
            .onChange(of: compactHeight) { _, height in AppDelegate.shared?.resizeResult(height: height) }
    }
    private var compactHeight: CGFloat {
        let text = store.translationError.isEmpty ? store.output : store.translationError
        let bounds = (text as NSString).boundingRect(with: NSSize(width: 296, height: 10000), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: NSFont.systemFont(ofSize: 16)], context: nil)
        return min(360, max(88, ceil(bounds.height * 1.3) + 36))
    }
}

@MainActor
struct GlossaryView: View {
    @ObservedObject var store: AppStore
    @State private var search = ""
    @State private var editing: Term?
    var filtered: [Term] {
        store.terms.filter { search.isEmpty || [$0.english, $0.chinese, $0.note].contains { $0.localizedCaseInsensitiveContains(search) } }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("专业词库").font(.title3.bold())
                    Text("按上下文优先采用你的译法，支持中英双向匹配。").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("添加词条") { editing = Term(english: "", chinese: "") }.buttonStyle(.borderedProminent)
            }
            HStack {
                TextField("搜索英文、中文或备注", text: $search).textFieldStyle(.roundedBorder)
                Button("导入词库") { store.importFile() }
                Menu("更多") {
                    Button("下载 CSV 模板") { store.exportFile(template: true) }
                    Button("导出完整词库") { store.exportFile() }
                }
                Button("撤销") { store.undo() }.disabled(!store.canUndo)
            }
            if store.terms.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "books.vertical").font(.system(size: 38)).foregroundStyle(.blue.opacity(0.8))
                    Text("让专业词汇保持一致").font(.headline)
                    Text("例如 chargeback → 拒付\n导入 CSV、TSV、JSON，或手动添加词条。").multilineTextAlignment(.center).foregroundStyle(.secondary)
                    Button("下载导入模板") { store.exportFile(template: true) }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filtered) { term in
                    HStack(alignment: .top, spacing: 12) {
                        Toggle("启用 \(term.english)", isOn: Binding(get: { term.enabled }, set: { value in
                            var next = term; next.enabled = value
                            do { try store.saveTerm(next) } catch { store.notice = error.localizedDescription }
                        })).labelsHidden().toggleStyle(.checkbox)
                        VStack(alignment: .leading, spacing: 5) {
                            HStack { Text(term.english).fontWeight(.medium); Image(systemName: "arrow.left.arrow.right").foregroundStyle(.tertiary); Text(term.chinese) }
                            if !term.note.isEmpty { Text(term.note).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                        }.opacity(term.enabled ? 1 : 0.5)
                        Spacer()
                        Button("编辑") { editing = term }
                        Button { do { try store.changeTerms(store.terms.filter { $0.id != term.id }) } catch { store.notice = error.localizedDescription } } label: {
                            Image(systemName: "trash").foregroundStyle(.secondary)
                        }.help("删除词条，可撤销").accessibilityLabel("删除 \(term.english)")
                    }.padding(.vertical, 7)
                }.listStyle(.inset).clipShape(RoundedRectangle(cornerRadius: 8))
            }
            Text("共 \(store.terms.count) 条 · 仅命中的启用词条会发送给所选模型。导入前可预览；相同英文词条会更新译法。").font(.caption).foregroundStyle(.secondary)
        }.padding(18)
        .sheet(item: $editing) { term in TermEditor(store: store, term: term) }
        .sheet(isPresented: Binding(get: { store.importPreview != nil }, set: { if !$0 { store.importPreview = nil } })) { ImportPreviewView(store: store) }
    }
}

@MainActor
struct TermEditor: View {
    @ObservedObject var store: AppStore
    @State var term: Term
    @State private var error = ""
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("编辑专业词条").font(.title2.bold())
            Form {
                TextField("英文 / 缩写", text: $term.english)
                TextField("中文译法", text: $term.chinese)
                TextField("适用场景 / 备注", text: $term.note)
                Toggle("启用这个词条", isOn: $term.enabled)
            }.textFieldStyle(.roundedBorder)
            if !error.isEmpty { Text(error).foregroundStyle(.red).font(.caption) }
            HStack { Spacer(); Button("取消") { dismiss() }; Button("保存词条") {
                do { try store.saveTerm(term); dismiss() } catch { self.error = error.localizedDescription }
            }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction) }
        }.padding(24).frame(width: 500)
    }
}

@MainActor
struct ImportPreviewView: View {
    @ObservedObject var store: AppStore
    var body: some View {
        let incoming = store.importPreview ?? []
        let result = Glossary.merge(incoming, into: store.terms)
        VStack(alignment: .leading, spacing: 16) {
            Text("确认导入词库").font(.title2.bold())
            Text("共 \(incoming.count) 条：新增 \(result.added) 条，更新 \(result.updated) 条。")
            Text("相同英文词条的译法、备注和启用状态会被更新；其他现有词条保留。导入后可以撤销。").font(.callout).foregroundStyle(.secondary)
            List(incoming.prefix(10)) { term in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(term.english) → \(term.chinese)")
                    if !term.note.isEmpty { Text(term.note).font(.caption).foregroundStyle(.secondary) }
                }
            }.frame(height: 240)
            if incoming.count > 10 { Text("预览前 10 条").font(.caption).foregroundStyle(.secondary) }
            HStack { Spacer(); Button("取消") { store.importPreview = nil }; Button("合并导入") { store.applyImport() }.buttonStyle(.borderedProminent) }
        }.padding(24).frame(width: 550)
    }
}

@MainActor
struct SettingsView: View {
    @ObservedObject var store: AppStore
    @State private var draft = ModelConfig()
    @State private var newKey = ""
    @State private var feedback = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("模型连接").font(.title3.bold())
                Form {
                    Picker("服务商", selection: $draft.provider) {
                        ForEach(["自定义", "豆包 / 火山方舟", "OpenAI", "DeepSeek", "本机模型"], id: \.self) { Text($0).tag($0) }
                    }
                    TextField("Base URL", text: $draft.baseURL, prompt: Text("https://你的服务地址/v1"))
                    TextField("模型 / Endpoint ID", text: $draft.model, prompt: Text("填写服务商提供的模型名称"))
                    SecureField("API Key", text: $newKey, prompt: Text(KeyVault.contains(draft.credentialAccount) ? "已保存在钥匙串，留空保留" : "仅保存到 macOS 钥匙串"))
                }.textFieldStyle(.roundedBorder)
                Text("支持 Chat Completions 格式。豆包可填写 Model ID 或推理接入点 ID；本机模型不需要 Key。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("保存模型配置") {
                        do { try store.saveConfig(draft, newKey: newKey); newKey = ""; feedback = "已保存，可返回翻译页试译。" }
                        catch { feedback = error.localizedDescription }
                    }.buttonStyle(.borderedProminent)
                    Button("试译 Hello world") {
                        do { try store.saveConfig(draft, newKey: newKey); newKey = ""; store.tab = "translate"; store.translate("Hello world") }
                        catch { feedback = error.localizedDescription }
                    }
                    Spacer()
                }
                if !feedback.isEmpty { Text(feedback).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
                Divider()
                Text("快捷键与取词").font(.headline)
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(store.hotkeyStatus)
                        Text(store.accessibilityGranted ? "辅助功能权限已开启" : "辅助功能权限未开启，仍可在主窗口粘贴翻译")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("刷新状态") { store.refreshPermissions(); AppDelegate.shared?.registerHotKey() }
                    Button("打开权限设置") { AppDelegate.shared?.openPermissionSettings() }
                }
                Text("选中文字后按 ⌘E，译文会出现在浮窗。双击应用图标可重新打开主窗口。").font(.caption).foregroundStyle(.secondary)
                Divider()
                Text("原文与命中的词条会发送到上面配置的模型服务。词库保存在本机；应用不保存翻译历史。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(20)
        }
        .onAppear { draft = store.config }
        .onChange(of: draft.provider) { _, provider in
            let urls = ["豆包 / 火山方舟": "https://ark.cn-beijing.volces.com/api/v3", "OpenAI": "https://api.openai.com/v1", "DeepSeek": "https://api.deepseek.com", "本机模型": "http://localhost:11434/v1"]
            if let base = urls[provider], draft.provider != store.config.provider { draft.baseURL = base; draft.model = ""; newKey = ""; feedback = "" }
        }
    }
}
