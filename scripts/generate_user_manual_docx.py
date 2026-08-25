#!/usr/bin/env python3
"""Generate WeKnora end-user manual (Word .docx)."""

from __future__ import annotations

import datetime
from pathlib import Path

from docx import Document
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_LINE_SPACING
from docx.oxml.ns import qn
from docx.shared import Cm, Inches, Pt, RGBColor
from docx.oxml import OxmlElement

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "docs" / "WeKnora用户使用手册.docx"
LOGO = ROOT / "frontend" / "src" / "assets" / "img" / "weknora.png"
ASSETS = ROOT / "docs" / "manual-assets"
VERSION = "v0.7.2"

# Pre-rendered UI screenshots (SVG → PNG via qlmanage)
SCREENSHOTS = {
    "chat": ASSETS / "screenshot-4.svg.png",       # Agentic RAG / 对话
    "search": ASSETS / "screenshot-2.svg.png",     # 混合检索
    "wiki": ASSETS / "screenshot-3.svg.png",        # Wiki
    "kb": ASSETS / "screenshot-1.svg.png",          # 文档检索 / 知识库
}


def set_doc_defaults(doc: Document) -> None:
    section = doc.sections[0]
    section.top_margin = Cm(2.5)
    section.bottom_margin = Cm(2.5)
    section.left_margin = Cm(2.8)
    section.right_margin = Cm(2.5)
    normal = doc.styles["Normal"]
    normal.font.name = "PingFang SC"
    normal._element.rPr.rFonts.set(qn("w:eastAsia"), "PingFang SC")
    normal.font.size = Pt(11)
    normal.paragraph_format.line_spacing_rule = WD_LINE_SPACING.MULTIPLE
    normal.paragraph_format.line_spacing = 1.35
    for level in range(1, 4):
        h = doc.styles[f"Heading {level}"]
        h.font.name = "PingFang SC"
        h._element.rPr.rFonts.set(qn("w:eastAsia"), "PingFang SC")
        h.font.color.rgb = RGBColor(0x07, 0x63, 0xA3)


def add_toc_field(doc: Document) -> None:
    p = doc.add_paragraph()
    run = p.add_run()
    fld = OxmlElement("w:fldSimple")
    fld.set(qn("w:instr"), 'TOC \\o "1-3" \\h \\z \\u')
    run._r.append(fld)
    doc.add_page_break()


def add_cover(doc: Document) -> None:
    for _ in range(3):
        doc.add_paragraph()
    if LOGO.exists():
        p = doc.add_paragraph()
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        p.add_run().add_picture(str(LOGO), width=Inches(2.8))
    t = doc.add_paragraph()
    t.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r = t.add_run("WeKnora 用户使用手册")
    r.bold = True
    r.font.size = Pt(28)
    r.font.color.rgb = RGBColor(0x07, 0x63, 0xA3)
    sub = doc.add_paragraph()
    sub.alignment = WD_ALIGN_PARAGRAPH.CENTER
    sr = sub.add_run(f"版本 {VERSION}  ·  企业知识库与智能问答平台")
    sr.font.size = Pt(14)
    sr.font.color.rgb = RGBColor(0x66, 0x66, 0x66)
    meta = doc.add_paragraph()
    meta.alignment = WD_ALIGN_PARAGRAPH.CENTER
    meta.add_run(f"\n生成日期：{datetime.date.today().isoformat()}\n").font.size = Pt(10)
    doc.add_page_break()


def h1(doc: Document, text: str) -> None:
    doc.add_heading(text, level=1)


def h2(doc: Document, text: str) -> None:
    doc.add_heading(text, level=2)


def h3(doc: Document, text: str) -> None:
    doc.add_heading(text, level=3)


def p(doc: Document, text: str) -> None:
    doc.add_paragraph(text)


def note(doc: Document, text: str) -> None:
    para = doc.add_paragraph()
    r = para.add_run("提示：" + text)
    r.italic = True
    r.font.color.rgb = RGBColor(0x55, 0x55, 0x55)


def warn(doc: Document, text: str) -> None:
    para = doc.add_paragraph()
    r = para.add_run("注意：" + text)
    r.bold = True
    r.font.color.rgb = RGBColor(0xC0, 0x39, 0x2B)


def steps(doc: Document, items: list[str]) -> None:
    for i, item in enumerate(items, 1):
        doc.add_paragraph(f"{i}. {item}", style="List Number")


def bullets(doc: Document, items: list[str]) -> None:
    for item in items:
        doc.add_paragraph(item, style="List Bullet")


def ui_figure(
    doc: Document,
    title: str,
    description: str,
    path_hint: str = "",
    image: Path | None = None,
) -> None:
    """Insert a figure with optional screenshot and caption."""
    if image and image.exists():
        pic = doc.add_paragraph()
        pic.alignment = WD_ALIGN_PARAGRAPH.CENTER
        pic.add_run().add_picture(str(image), width=Inches(5.8))
    else:
        box = doc.add_table(rows=1, cols=1)
        box.style = "Table Grid"
        cell = box.cell(0, 0)
        cell.text = "（界面示意图占位，可替换为实际部署环境截图）"
        for para in cell.paragraphs:
            for run in para.runs:
                run.font.size = Pt(10)
                run.font.color.rgb = RGBColor(0x99, 0x99, 0x99)
    cap = doc.add_paragraph()
    cap.alignment = WD_ALIGN_PARAGRAPH.CENTER
    cr = cap.add_run(f"图：{title}")
    cr.bold = True
    cr.font.size = Pt(10)
    desc = doc.add_paragraph(description + (f"\n界面路径：{path_hint}" if path_hint else ""))
    desc.alignment = WD_ALIGN_PARAGRAPH.CENTER
    for run in desc.runs:
        run.font.size = Pt(9)
        run.font.color.rgb = RGBColor(0x55, 0x55, 0x55)
    doc.add_paragraph()


def table(doc: Document, headers: list[str], rows: list[list[str]]) -> None:
    t = doc.add_table(rows=1 + len(rows), cols=len(headers))
    t.style = "Light Grid Accent 1"
    hdr = t.rows[0].cells
    for i, h in enumerate(headers):
        hdr[i].text = h
        for run in hdr[i].paragraphs[0].runs:
            run.bold = True
    for ri, row in enumerate(rows):
        for ci, val in enumerate(row):
            t.rows[ri + 1].cells[ci].text = val
    doc.add_paragraph()


def build_manual() -> Document:
    doc = Document()
    set_doc_defaults(doc)
    add_cover(doc)

    h1(doc, "文档说明")
    p(doc, "本手册面向 WeKnora 最终用户（业务人员、知识管理员、空间 Owner/Admin），说明从登录、建库、上传文档、配置智能体到对话检索的完整操作流程。")
    p(doc, "若贵司部署在子路径（例如 http://10.121.1.155:8081/weknora/login），请在浏览器中使用完整地址访问；LDAP 部署环境下通常仅支持企业账号登录。")
    note(doc, "打开 Word 后，在目录页右键选择「更新域 → 更新整个目录」，即可生成可点击的章节目录。")
    note(doc, "管理员（模型、存储、向量库、系统队列等）操作需 Admin 或 SystemAdmin 权限，普通成员以 Contributor/Viewer 权限为主。")
    h2(doc, "阅读指引")
    table(doc, ["符号", "含义"], [
        ["编号步骤", "必须按顺序执行的操作"],
        ["提示", "建议或可选优化"],
        ["注意", "常见误操作或不可逆后果"],
        ["图 + 界面路径", "对应功能在系统中的导航位置"],
    ])

    h1(doc, "目录")
    add_toc_field(doc)

    # ---- 1 登录 ----
    h1(doc, "第1章  登录与账号")
    h2(doc, "1.1 访问系统")
    steps(doc, [
        "打开浏览器（推荐 Chrome / Edge 最新版）。",
        "在地址栏输入部署地址，例如：http://10.x.x.x:8081/weknora/login。",
        "若页面空白或静态资源 404，请联系管理员确认 FRONTEND_BASE_PATH 与 UI 镜像版本一致。",
    ])
    ui_figure(
        doc,
        "登录页",
        "页面左侧为产品能力轮播（Agentic RAG、混合检索、Wiki、文档解析）；右侧为登录表单。\n"
        "• 账号：LDAP 用户名或注册邮箱\n"
        "• 密码：LDAP/本地密码\n"
        "• 右上角：语言切换（中/英等）",
        "/weknora/login",
        image=SCREENSHOTS.get("chat"),
    )

    h2(doc, "1.2 LDAP 登录（企业常见）")
    steps(doc, [
        "输入 LDAP 账号（mail 或 uid，以管理员配置为准）。",
        "输入 LDAP 密码，点击「登录」。",
        "首次 LDAP 登录会自动在 WeKnora 创建本地用户记录；若需被邀请进共享空间，请确保 LDAP 中配置了 mail 属性。",
    ])
    warn(doc, "LDAP-only 环境已关闭本地密码注册；勿使用「邀请链接注册」创建本地账号，否则与 LDAP 账号脱节。")

    h2(doc, "1.3 邀请链接注册（非 LDAP-only 环境）")
    steps(doc, [
        "空间 Owner 在「设置 → 成员 → 共享邀请链接」生成链接。",
        "完整链接格式示例：http://10.121.1.155:8081/weknora/register?token=xxxx（子路径部署必须含 /weknora）。",
        "打开链接，填写邮箱、用户名、密码完成注册并自动加入空间。",
        "注册成功后进入平台首页；若链接过期请联系管理员重新生成。",
    ])

    h2(doc, "1.4 个人菜单与退出")
    steps(doc, [
        "点击左上角用户头像，打开个人菜单。",
        "可进入「全部设置」「系统管理（仅 SystemAdmin）」等。",
        "点击「退出登录」安全注销；会清除本地会话缓存。",
    ])
    ui_figure(doc, "用户菜单", "显示当前空间名、角色；可切换空间、进入设置、退出。", "左上角头像", image=LOGO if LOGO.exists() else None)

    # ---- 2 空间 ----
    h1(doc, "第2章  工作区（空间）")
    h2(doc, "2.1 概念")
    p(doc, "WeKnora 以「工作区 / 空间（Workspace/Tenant）」隔离数据：知识库、智能体、成员、存储配置均属于某个空间。一个用户可加入多个空间。")
    table(doc, ["概念", "说明"], [
        ["Home 空间", "用户首次登录后的默认个人空间"],
        ["共享空间成员", "被邀请或通过邀请链接加入的其他空间"],
        ["角色", "Owner / Admin / Contributor / Viewer，决定菜单与写权限"],
    ])

    h2(doc, "2.2 切换空间")
    steps(doc, [
        "点击左上角头像，在「当前空间」区域 hover 显示空间列表。",
        "点击目标空间名称完成切换；页面会刷新并加载该空间的资源。",
        "若具备权限，可点击「创建工作区」填写名称与描述。",
    ])

    h2(doc, "2.3 空间信息与删除")
    steps(doc, [
        "进入「设置 → 空间信息」查看名称、描述、存储用量。",
        "Owner 可修改空间名称/描述；删除空间需输入空间名确认，会 purge 成员关系。",
    ])
    warn(doc, "删除空间不可恢复，请先迁移或导出重要知识库。")

    # ---- 3 知识库 ----
    h1(doc, "第3章  知识库")
    h2(doc, "3.1 创建知识库")
    steps(doc, [
        "侧栏进入「知识库」列表，点击「新建知识库」。",
        "填写名称、描述；选择类型（文档库 / FAQ 等，视版本而定）。",
        "选择 Embedding 模型、可选 Rerank；配置存储引擎（使用空间默认或指定实例）。",
        "保存后进入知识库详情页。",
    ])
    ui_figure(
        doc,
        "新建知识库向导",
        "分步配置：基本信息 → 分块策略 → 多模态/ASR → 图谱（可选）→ 高级索引。",
        "平台 / 知识库 / 新建",
        image=SCREENSHOTS.get("kb"),
    )

    h2(doc, "3.2 知识库设置（分块与解析）")
    bullets(doc, [
        "分块策略：自动 / 按标题 / 自定义分隔符；可启用父子块（Parent-Child）。",
        "解析引擎：PDF/Office 等走 DocReader；可配置 MinerU、PaddleOCR-VL 等规则。",
        "多模态：图片 PDF 需开启 VLM 并配置模型，否则可能解析为空文本。",
        "问题生成：入库时自动生成推荐问题，供检索增强。",
        "Wiki / 图谱索引：开启后额外构建 Wiki 页面或知识图谱（需 Neo4j 等组件）。",
    ])
    note(doc, "保存知识库时若开启图谱抽取（extract_config.enabled），必须填写示例文本与标签，否则会报 text cannot be empty。")

    h2(doc, "3.3 上传文档")
    steps(doc, [
        "进入目标知识库 →「文档」Tab。",
        "点击「添加」：支持本地文件、文件夹、URL、手动 Markdown、数据源同步等。",
        "上传确认对话框可调整本次 batch 的 process_config（解析/OCR/分块覆盖项）。",
        "确认后开始异步解析；列表显示进度，完成后可检索。",
    ])
    ui_figure(
        doc,
        "上传确认",
        "左：文件列表；右：解析引擎、分块、多模态等覆盖项。\n确认后任务进入队列，可在时间线查看阶段进度。",
        "知识库 / 文档 / 添加",
        image=SCREENSHOTS.get("kb"),
    )

    h2(doc, "3.4 数据源同步")
    steps(doc, [
        "添加 → 数据源：选择已配置的数据源类型（如飞书文档、RSS、Web 等）。",
        "勾选要同步的目录或 URL 规则，设置同步频率（若支持）。",
        "首次同步会批量创建文档任务；后续增量更新已同步条目。",
        "在数据源管理页可查看上次同步时间与失败条目。",
    ])

    h2(doc, "3.5 标签管理")
    steps(doc, [
        "知识库 → 标签：创建标签名称与颜色。",
        "在文档列表为单条或多选文档批量打标签。",
        "检索与 Agent 工具可按标签过滤文档范围。",
    ])
    h2(doc, "3.6 文档操作")
    table(doc, ["操作", "步骤", "权限"], [
        ["预览/下载", "点击文档行 → 预览抽屉", "Viewer+"],
        ["编辑标签", "文档行标签区或批量选择 → 管理标签", "Contributor+"],
        ["重新解析", "更多 → 重新解析，可带 process_config", "Contributor+"],
        ["批量重解析", "多选 → 批量重解析", "Contributor+"],
        ["删除", "更多 → 删除，确认", "Admin+"],
    ])

    h2(doc, "3.7 手动知识")
    steps(doc, [
        "添加 → 手动创建，输入标题与 Markdown 正文。",
        "可选择「保存草稿」或「发布」；正文不能为空。",
        "发布后走与普通文档相同的索引流程。",
    ])

    h2(doc, "3.8 FAQ 知识库")
    steps(doc, [
        "在 FAQ 类型知识库中进入 FAQ 管理。",
        "添加标准问、相似问、答案；支持导入。",
        "FAQ 条目独立向量化，供 FAQ 检索与 Agent 工具使用。",
    ])

    # ---- 4 Wiki & Graph ----
    h1(doc, "第4章  Wiki 与知识图谱")
    h2(doc, "4.1 Wiki 浏览器")
    steps(doc, [
        "知识库内切换到「Wiki」Tab，左侧为目录树，右侧为页面正文。",
        "支持文件夹 CRUD、页面移动、分类层级。",
        "索引任务完成后 Wiki 页面自动生成/更新。",
    ])

    ui_figure(
        doc,
        "Wiki 知识库",
        "左侧目录树按文档结构组织；右侧为 Wiki 页面正文，支持层级分类与全文检索。",
        "知识库 / Wiki",
        image=SCREENSHOTS.get("wiki"),
    )

    h2(doc, "4.2 图谱视图")
    steps(doc, [
        "切换到「图谱」Tab，查看实体关系网络。",
        "可搜索节点、按类型过滤、Ego 模式展开邻居。",
        "点击节点打开侧栏查看页面摘要与链接。",
    ])

    h2(doc, "4.3 图谱抽取配置")
    steps(doc, [
        "知识库设置 → 知识图谱：填写示例文本，选择关系标签。",
        "点击「生成文本 / 提取关系」（需 Admin+ 且 LLM 已配置）。",
        "保存 extract_config 并开启 graph_enabled 索引策略。",
    ])

    # ---- 5 Agent ----
    h1(doc, "第5章  智能体（Agent）")
    h2(doc, "5.1 创建智能体")
    steps(doc, [
        "侧栏「智能体」→「新建」。",
        "填写名称、描述；选择类型预设（RAG / 数据分析等）。",
        "绑定 LLM 模型；配置系统 Prompt、上下文模板。",
        "关联一个或多个知识库；可选开启网络搜索、MCP 工具、Skills。",
        "配置引用输出、思考链、推荐问题等 v0.7 新特性。",
    ])
    ui_figure(
        doc,
        "智能体编辑器",
        "左侧导航：基本信息 / Prompt / 工具 / 知识库 / 建议问题等。\n保存前会校验模型是否就绪。",
        "平台 / 智能体 / 编辑",
        image=SCREENSHOTS.get("chat"),
    )

    h2(doc, "5.2 工具与 MCP")
    bullets(doc, [
        "内置工具：知识库搜索、Grep、文档信息、数据分析（CSV/Excel）等。",
        "MCP 服务：在设置中注册外部 MCP，Agent 中勾选启用；支持 OAuth 中途授权。",
        "Skills：对话中用 @技能名 限定本轮可用技能。",
    ])

    h2(doc, "5.3 共享智能体")
    p(doc, "可将智能体共享到「共享空间」，供组织内其他空间成员在对话中选择（只读共享）。")

    # ---- 6 Chat ----
    h1(doc, "第6章  对话与检索")
    h2(doc, "6.1 发起对话")
    steps(doc, [
        "侧栏「新建对话」或从知识库/智能体页进入。",
        "选择智能体（决定工具与 Prompt）；可选绑定知识库。",
        "在底部输入框输入问题；可 @ 文件、@ Skill、@ MCP。",
        "支持粘贴/上传图片与附件（v0.7 临时附件，有数量上限）。",
        "Enter 发送；生成过程中可点击停止。",
    ])
    ui_figure(
        doc,
        "对话界面",
        "中：消息流（思考块、工具时间线、引用）；侧：会话列表。\n底部：模型/Agent 选择、附件、发送。",
        "平台 / 对话",
        image=SCREENSHOTS.get("chat"),
    )

    h2(doc, "6.2 引用与检索")
    ui_figure(
        doc,
        "混合检索策略",
        "系统可同时使用 BM25 关键词、向量语义与知识图谱关系进行召回与重排，提高问答准确度。",
        "知识库设置 / 检索策略",
        image=SCREENSHOTS.get("search"),
    )
    bullets(doc, [
        "回答中的引用角标可点击查看 chunk 来源。",
        "「引用」抽屉列出 KB/Web 来源；Agent 可关闭正文引用但仍保留抽屉条目。",
        "RAG 时间线展示检索、重排、合并阶段进度。",
        "对话结束后可显示推荐追问。",
    ])

    h2(doc, "6.3 知识库内检索")
    steps(doc, [
        "侧栏「知识检索」，选择知识库与查询方式（语义/混合）。",
        "输入问题，查看命中文档块与得分。",
    ])

    h2(doc, "6.4 会话管理")
    bullets(doc, [
        "侧栏按来源筛选：Web / IM / Embed 等。",
        "可重命名会话标题、删除历史。",
        "消息索引（可选）：开启后会话消息写入向量库供语义搜索。",
    ])

    # ---- 7 Members ----
    h1(doc, "第7章  成员与邀请")
    h2(doc, "7.1 按邮箱邀请")
    steps(doc, [
        "设置 → 成员 → 输入邮箱、选择角色（Contributor/Admin 等）。",
        "被邀请人须已在系统中存在（LDAP 用户需先登录一次）。",
        "对方登录后在「我的邀请」接受。",
    ])

    h2(doc, "7.2 共享邀请链接")
    steps(doc, [
        "成员页 →「共享邀请链接」→ 选择角色 → 生成。",
        "复制链接（子路径部署须含 /weknora/register?token=…）。",
        "链接可多次使用，直到过期或被撤销。",
    ])
    warn(doc, "LDAP-only 环境请勿用邀请链接注册本地账号。")

    h2(doc, "7.3 角色说明（空间内）")
    table(doc, ["角色", "典型权限"], [
        ["Owner", "空间全部设置、成员、删除空间、API Key"],
        ["Admin", "成员管理、存储/模型/KB 设置、邀请"],
        ["Contributor", "上传文档、编辑 KB、对话"],
        ["Viewer", "只读检索与对话（视配置）"],
    ])

    # ---- 8 Organization ----
    h1(doc, "第8章  共享空间（组织）")
    p(doc, "共享空间用于跨工作区共享知识库与智能体，详见《共享空间说明》。")
    h2(doc, "8.1 创建与加入")
    steps(doc, [
        "侧栏「组织」→ 创建组织，填写名称。",
        "管理员生成邀请码或邀请链接；成员输入邀请码加入。",
        "若开启审批，提交申请后由管理员通过。",
    ])

    h2(doc, "8.2 共享知识库")
    steps(doc, [
        "组织设置 → 共享知识库 → 选择本空间 KB → 设置只读/可写 → 共享。",
        "成员在知识库列表中看到「组织共享」条目。",
    ])

    h2(doc, "8.3 组织角色")
    table(doc, ["角色", "能力"], [
        ["管理员", "设置、成员、邀请码、审批、管理全部共享"],
        ["编辑者", "编辑共享 KB 内容，共享自己的 KB"],
        ["只读", "查看与检索共享 KB"],
    ])

    # ---- 9 Integrations ----
    h1(doc, "第9章  集成中心")
    h2(doc, "9.1 即时通讯（IM）")
    bullets(doc, [
        "支持企业微信、钉钉、飞书/Lark、Slack、Telegram、QQBot 等（视部署启用）。",
        "集成 → IM：创建渠道，绑定 Agent，配置回调/Token。",
        "用户在 IM 中 @ 机器人即可问答，会话出现在 Web 侧栏。",
    ])

    h2(doc, "9.2 网站嵌入（Embed）")
    steps(doc, [
        "集成 → Embed：创建渠道，绑定 Agent，配置域名白名单。",
        "复制 weknora-widget.js 嵌入代码到目标网站。",
        "可选 Secure Mode：publish token 换 session token。",
    ])

    h2(doc, "9.3 API Key（v0.7）")
    steps(doc, [
        "集成 → API：创建 Key，勾选能力（manage_kbs、manage_storage_backends 等）。",
        "可限制到特定知识库；在 Playground 测试 REST 调用。",
        "妥善保管 Secret；泄露后立即轮换。",
    ])

    # ---- 10 Settings ----
    h1(doc, "第10章  空间设置（管理员）")
    h2(doc, "10.1 模型管理")
    steps(doc, [
        "设置 → 模型：添加 Chat / Embedding / Rerank / VLM / ASR。",
        "填写 Provider、Base URL、API Key、模型名；点击测试连接。",
        "Embedding 需填写维度（如 1024）；与向量库索引维度一致。",
    ])

    h2(doc, "10.2 存储引擎（v0.7 多实例）")
    steps(doc, [
        "设置 → 存储引擎：查看 env 只读实例与用户创建的实例。",
        "新建实例（MinIO/S3/COS 等）→ 测试连通性 → 保存。",
        "某一实例「设为默认」：新建 KB 未指定时使用。",
        "已有文件的 KB 改存储需走迁移流程，不可直接改绑定。",
    ])
    note(doc, "app 容器需配置 FRONTEND_BASE_PATH 与 STORAGE_TYPE 等环境变量；多实例在 UI 管理。")

    h2(doc, "10.3 向量数据库")
    steps(doc, [
        "设置 → 向量库：注册 Qdrant / PostgreSQL(pgvector) / Elasticsearch 等实例。",
        "知识库创建时选择向量库；维度必须与 Embedding 一致。",
    ])

    h2(doc, "10.4 解析引擎")
    p(doc, "配置 DocReader 地址、MinerU/PaddleOCR-VL 等；影响全局 PDF/扫描件解析质量。")

    h2(doc, "10.5 网络搜索")
    p(doc, "注册 SearXNG、Bing、Google 等 Provider；Agent 开启 web_search 后可用。")

    h2(doc, "10.6 MCP 服务")
    steps(doc, [
        "设置 → MCP：添加远程或内置 MCP，配置 URL/Headers/OAuth。",
        "测试连接后在 Agent 中启用。",
    ])

    h2(doc, "10.7 系统管理（SystemAdmin）")
    bullets(doc, [
        "系统设置：注册策略、默认配额、SSRF 白名单等。",
        "运行时队列：查看 ingestion 队列深度、失败任务重试。",
        "内置模型 YAML、用户密码重置等。",
    ])

    # ---- 11 FAQ ----
    h1(doc, "第11章  常见问题")
    table(doc, ["现象", "原因与处理"], [
        ["text can not empty / text cannot be empty", "Embedding 收到空文本：检查扫描 PDF 是否开 OCR；或图谱配置 enabled 但示例文本为空"],
        ["上传后一直 processing", "查看运行时队列；确认 Embedding/DocReader 模型可用"],
        ["图片不显示", "检查 MinIO/S3 存储、bucket 权限、MINIO_PUBLIC_ENDPOINT"],
        ["LDAP 用户收不到邮箱邀请", "需先 LDAP 登录一次；邀请邮箱与 LDAP mail 一致"],
        ["邀请链接缺 /weknora", "升级 UI 镜像并配置 FRONTEND_BASE_PATH"],
        ["Viewer 无法对话", "检查角色权限；v0.6+ 已修复 Viewer 对话门控"],
    ])

    h1(doc, "附录 A  快捷键与习惯")
    bullets(doc, [
        "对话输入框：Enter 发送，Shift+Enter 换行（以实际 UI 为准）。",
        "文档列表：支持框选批量操作。",
        "设置修改后若页面闪回旧值，尝试无痕窗口排除浏览器插件干扰。",
    ])

    h1(doc, "附录 B  术语表")
    table(doc, ["术语", "含义"], [
        ["Chunk", "文档分块，检索最小单元"],
        ["RAG", "检索增强生成"],
        ["Tenant/Workspace", "工作区/空间"],
        ["Organization", "共享空间/组织"],
        ["MCP", "Model Context Protocol 外部工具协议"],
    ])

    h1(doc, "附录 C  替换为现场截图（可选）")
    p(doc, "本手册已嵌入产品官方界面示意图。若需更贴合贵司部署环境，管理员可在以下页面自行截图并替换 Word 中对应图片：")
    bullets(doc, [
        "登录页、首页侧栏布局",
        "知识库文档列表与上传对话框",
        "智能体编辑页、对话页（含引用抽屉）",
        "设置 → 成员 / 存储引擎 / 模型管理",
    ])
    p(doc, "在 Word 中右键图片 →「更改图片」即可替换，无需重新生成脚本。")

    h1(doc, "附录 D  版本与联系")
    p(doc, f"本手册对应 WeKnora {VERSION}。功能以实际部署镜像为准；升级后请关注数据库 migration 与 .env 中 WEKNORA_VERSION。")
    p(doc, "遇到系统级故障（队列堆积、模型不可用、存储连通性）请联系空间 Admin 或 SystemAdmin。")

    if LOGO.exists():
        doc.add_paragraph()
        end = doc.add_paragraph()
        end.alignment = WD_ALIGN_PARAGRAPH.CENTER
        end.add_run().add_picture(str(LOGO), width=Inches(1.2))

    return doc


def ensure_assets() -> None:
    """Convert SVG screenshots to PNG if assets dir is missing."""
    ASSETS.mkdir(parents=True, exist_ok=True)
    img_dir = ROOT / "frontend" / "src" / "assets" / "img"
    import shutil
    import subprocess

    for name in ("screenshot-1", "screenshot-2", "screenshot-3", "screenshot-4"):
        png = ASSETS / f"{name}.svg.png"
        svg = img_dir / f"{name}.svg"
        if png.exists() or not svg.exists():
            continue
        subprocess.run(
            ["qlmanage", "-t", "-s", "1400", "-o", str(ASSETS), str(svg)],
            check=False,
            capture_output=True,
        )
    if LOGO.exists() and not (ASSETS / "weknora.png").exists():
        shutil.copy(LOGO, ASSETS / "weknora.png")


def main() -> None:
    ensure_assets()
    OUT.parent.mkdir(parents=True, exist_ok=True)
    doc = build_manual()
    doc.save(str(OUT))
    print(f"Wrote {OUT} ({OUT.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
