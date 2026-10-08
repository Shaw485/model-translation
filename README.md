# model-translation

应用名称：CmdETranslate。

macOS 大模型翻译工具。保留 **⌘E 选词翻译**，增加可见主窗口、模型设置和专业词库。使用配置的大模型服务，不调用苹果或谷歌翻译。

## 使用

1. 打开 `CmdETranslate.app`，进入「模型设置」。
2. 选择服务商，填写接口地址、模型名称 / Endpoint ID、API Key，点击「保存模型配置」。Key 保存在 macOS 钥匙串中，不写入配置文件。
3. 点击「试译 Hello world」验证真实模型连接。应用中的服务商名称是接口预设，具体模型需使用你账户中可用的 Model ID。
4. 在其他应用选中文字，按 **⌘E**；或在主窗口粘贴原文，点击「使用模型翻译」。
5. 在「专业词库」手动添加词条，或点击「导入词库」上传本机文件。

双击图标会显示主窗口；关闭主窗口后仍可通过菜单栏「译」重新打开。退出应用使用菜单栏「退出」或 ⌘Q。

译文浮窗可通过点击外部、按 Esc、右上角关闭按钮收起。点击浮窗内部、选择译文或复制时保持打开。

## 模型接口

采用 Chat Completions 兼容格式。填写 Base URL 或完整 `/chat/completions` 地址均可。

| 服务商 | Base URL |
| --- | --- |
| OpenAI | `https://api.openai.com/v1` |
| 豆包 / 火山方舟 | `https://ark.cn-beijing.volces.com/api/v3` |
| DeepSeek | `https://api.deepseek.com` |
| 本机兼容服务 | 例如 `http://localhost:11434/v1` |

远程服务使用 HTTPS 和对应的 API Key；本机服务可以不填 Key。不同服务地址分别保管 Key，切换地址不会把原服务的 Key 自动发送给新服务。拒绝 HTTP 重定向。API 调用可能产生所选服务商的费用。

接口参考：[OpenAI](https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create)、[火山方舟](https://docs.volcengine.com/docs/ark/chat-api?lang=zh&redirect=1)、[DeepSeek](https://api-docs.deepseek.com/)。

DeepSeek 官方接口请求保留推理，强度设置为 `low`。紧凑译文浮窗仅显示译文、复制和关闭按钮，高度随内容调整，长文可滚动。

## 专业词库

支持 UTF-8 CSV、TSV（TXT 按制表符解析）、JSON。可直接从 Excel 导出 UTF-8 CSV。建议先下载应用中的模板。

```csv
英文,中文,备注,启用
chargeback,拒付,支付场景,true
returnless refund,免退货退款,售后场景,true
SLA,服务水平协议,服务承诺,true
```

JSON 格式：

```json
[
  {"english":"chargeback","chinese":"拒付","note":"支付场景","enabled":true}
]
```

- 英文、中文必填；备注、启用可选。最多 5,000 条、2 MB。
- 导入前显示预览。相同英文（忽略大小写）会更新译法、备注及启用状态；其他词条保留。
- 格式错误会拒绝整个文件，不进行部分导入。同一文件中存在重复英文时先合并再导入。
- 可以搜索、编辑、停用、删除、导出词库；支持撤销最近一次词库修改（当前运行期间）。
- 英译中匹配英文，中译英匹配中文。英文忽略大小写并按词边界匹配，优先把长词组交给模型。
- 仅命中的启用词条随原文发送给模型。术语是模型翻译约束，不是简单字符串替换；模型仍可能需要人工复核。

## 权限与数据

选词功能需要「系统设置 → 隐私与安全性 → 辅助功能 → CmdETranslate」。粘贴翻译不需要辅助功能权限。此本地构建使用临时签名，更新后系统可能要求重新确认权限。

取词优先读取选中文本；不支持时短暂调用复制并恢复剪贴板。未读到新文字时显示提示，不使用旧剪贴板冒充选中文本。

本地词库及模型配置保存在 `~/Library/Application Support/CmdETranslate/`；API Key 单独保存在钥匙串。应用不保存翻译历史，不记录 API Key 或原文日志。每次翻译会把原文及匹配词条发送到你配置的模型接口。

## 构建与检查

Apple Silicon，macOS 15+，Apple Command Line Tools，无第三方依赖。

```sh
bash build.sh
bash test.sh
```

测试覆盖词库解析、双向匹配、冲突合并、导入错误、接口地址校验、请求格式及错误响应，并使用 URLProtocol 固定响应验证异步请求链路。这些测试不代表真实模型调用成功；真实连接需配置有效凭证后通过「试译」验证。
