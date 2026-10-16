import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class WorkshopModel: ObservableObject {
    @Published var styles: [CustomNoteStyle]
    let store: CustomStyleStore
    @Published var draft = CustomNoteStyle() { didSet { schedulePreview() } }
    @Published var image: NSImage? { didSet { previewArtwork = nil; schedulePreview() } }
    @Published var sample = "今天也有值得记下的小事\n把灵感挂起来，慢慢完成。" { didSet { schedulePreview() } }
    @Published private(set) var preview = NSImage(size: NSSize(width: 140, height: 104))
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var isChoosing = false
    weak var window: NSWindow?
    private var openPanel: NSOpenPanel?
    private var loadID = UUID()
    private var previewTimer: Timer?
    private var previewArtwork: NSImage?
    private var renderedStyle: CustomNoteStyle?
    private var renderedSample: String?
    private let imageQueue = DispatchQueue(label: "app.tendedero.workshop.images", qos: .userInitiated)
    @Published var mode = "text"
    @Published var message: String?
    @Published var isError = false
    private var savedDraft = CustomNoteStyle()
    private var imageChanged = false
    var onSave: (NoteStyle) -> Void = { _ in }
    var onCancel: () -> Void = {}

    init(store: CustomStyleStore = .shared) {
        self.store = store
        styles = store.styles.filter { !$0.archived }
        savedDraft = draft
    }
    var dirty: Bool { draft != savedDraft || imageChanged || isLoading }
    var busy: Bool { isLoading || isSaving || isChoosing }

    private func schedulePreview() {
        guard previewTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.renderPreview() }
        }
        previewTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        RunLoop.main.add(timer, forMode: .modalPanel)
    }

    func renderPreview() {
        previewTimer?.invalidate()
        previewTimer = nil
        var style = draft
        // These controls change the overlay, not the bitmap.
        style.name = ""; style.clipX = 0; style.clipY = 0; style.tilt = 0
        guard renderedStyle != style || renderedSample != sample || previewArtwork == nil else { return }
        if previewArtwork == nil {
            previewArtwork = makeCustomNoteThumbnail("", style: style, artwork: image, pixelScale: 4)
        }
        preview = makeCustomNoteThumbnail(sample, style: style, artwork: previewArtwork, pixelScale: 4)
        renderedStyle = style
        renderedSample = sample
    }

    func cancelPendingWork() {
        loadID = UUID()
        isLoading = false
        openPanel?.cancel(nil)
        previewTimer?.invalidate()
        previewTimer = nil
    }

    // DispatchQueue.main callbacks can be deferred by a nested AppKit modal
    // loop. Deliver completions in its run-loop mode as well as normal mode.
    nonisolated private static func deliver(_ action: @escaping @MainActor () -> Void) {
        RunLoop.main.perform(inModes: [.default, .modalPanel, .eventTracking]) {
            MainActor.assumeIsolated { action() }
        }
        CFRunLoopWakeUp(CFRunLoopGetMain())
    }

    func confirmDiscard() -> Bool {
        guard dirty else { return true }
        let alert = NSAlert()
        alert.messageText = "放弃未保存的修改？"
        alert.addButton(withTitle: "继续编辑")
        alert.addButton(withTitle: "放弃修改")
        return alert.runModal() == .alertSecondButtonReturn
    }

    func select(_ style: CustomNoteStyle?) {
        guard !isSaving, !isChoosing else { return }
        guard confirmDiscard() else { return }
        cancelPendingWork()
        draft = style ?? CustomNoteStyle()
        savedDraft = draft
        image = style.flatMap { store.image(for: $0) }
        imageChanged = false
        message = nil
        isError = false
        mode = "text"
    }

    func chooseImage() {
        guard !busy, let window else { return }
        let panel = NSOpenPanel()
        panel.title = "选择便签底图"
        panel.allowedContentTypes = CustomStyleStore.importContentTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        isChoosing = true
        openPanel = panel
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            self.isChoosing = false
            self.openPanel = nil
            guard response == .OK, let url = panel.url else { return }
            self.load(url)
        }
    }

    func load(_ url: URL) {
        guard !isSaving, !isChoosing else { return }
        let id = UUID()
        loadID = id
        isLoading = true
        message = nil
        isError = false
        imageQueue.async { [weak self] in
            let result = Result { try CustomStyleStore.decodeImage(url) }
            Self.deliver {
                guard let self, self.loadID == id else { return }
                self.isLoading = false
                switch result {
                case let .success((cg, warning)):
                    self.image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                    self.imageChanged = true
                    self.message = warning ?? "底图已导入，可以调整文字区域后保存样式。"
                    if self.draft.name == "我的便签" {
                        self.draft.name = String(url.deletingPathExtension().lastPathComponent.prefix(40))
                    }
                case let .failure(error): self.fail(error)
                }
            }
        }
    }

    @discardableResult
    func drop(_ providers: [NSItemProvider]) -> Bool {
        guard !busy, let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else { return false }
        let id = UUID()
        loadID = id
        isLoading = true
        message = nil
        isError = false
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] value, error in
            let url: URL?
            if let value = value as? URL { url = value }
            else if let data = value as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
            else if let text = value as? String { url = URL(string: text) }
            else { url = nil }
            Self.deliver {
                guard let self, self.loadID == id else { return }
                self.isLoading = false
                if let url, url.isFileURL { self.load(url) }
                else { self.fail(error ?? WorkshopError.message("无法读取拖入的图片，请用“上传底图”选择文件。")) }
            }
        }
        return true
    }

    func save() {
        guard !busy, let image,
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let snapshot = draft
        isSaving = true
        message = nil
        imageQueue.async { [weak self] in
            let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
            Self.deliver {
                guard let self else { return }
                defer { self.isSaving = false }
                do {
                    guard let png else { throw WorkshopError.message("图片保存失败，请重新选择底图。") }
                    let savedImage = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                    let style = try self.store.save(snapshot, image: savedImage, png: png)
                    self.styles = self.store.styles.filter { !$0.archived }
                    self.draft = self.styles.first { $0.key == style.rawValue } ?? snapshot
                    self.savedDraft = self.draft
                    self.imageChanged = false
                    self.onSave(style)
                } catch { self.fail(error) }
            }
        }
    }

    func archive() {
        guard !busy else { return }
        guard styles.contains(where: { $0.id == draft.id }) else { return }
        let alert = NSAlert()
        alert.messageText = "从“我的样式”中移除？"
        alert.informativeText = "已经挂上的便签会保留原来的外形。"
        alert.addButton(withTitle: "取消")
        alert.addButton(withTitle: "移除样式")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        do {
            try store.archive(draft.id)
            styles = store.styles.filter { !$0.archived }
            savedDraft = draft
            imageChanged = false
            select(nil)
        } catch { fail(error) }
    }

    private func fail(_ error: Error) { message = error.localizedDescription; isError = true }
}

@MainActor
enum NoteWorkshop {
    private static var session: WorkshopSession?

    static func open(store: CustomStyleStore = .shared, parent: NSWindow? = nil,
                     completion: @escaping (NoteStyle?) -> Void = { _ in }) {
        if let session {
            session.completions.append(completion)
            session.window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let controller = WorkshopSession(store: store, parent: parent) { style in
            session = nil
            completion(style)
        }
        session = controller
        controller.show()
    }
}

@MainActor
private final class WorkshopSession: NSObject, NSWindowDelegate {
    let model: WorkshopModel
    let window: NSWindow
    weak var parent: NSWindow?
    var completions: [(NoteStyle?) -> Void]

    init(store: CustomStyleStore, parent: NSWindow?, completion: @escaping (NoteStyle?) -> Void) {
        let model = WorkshopModel(store: store)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 650),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        self.model = model
        self.window = window
        self.parent = parent
        self.completions = [completion]
        super.init()
        window.title = "便签工坊"
        window.minSize = NSSize(width: 900, height: 620)
        window.isReleasedWhenClosed = false
        window.delegate = self
        model.window = window
        model.onSave = { [weak self] in self?.finish($0) }
        model.onCancel = { [weak self] in
            guard let self else { return }
            _ = self.windowShouldClose(self.window)
        }
        window.contentView = NSHostingView(rootView: WorkshopView(model: model))
    }

    func show() {
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        if let parent { parent.beginSheet(window) }
        else { window.makeKeyAndOrderFront(nil) }
    }

    func finish(_ style: NoteStyle?) {
        guard !completions.isEmpty else { return }
        let callbacks = completions
        completions.removeAll()
        model.cancelPendingWork()
        if let parent { parent.endSheet(window) }
        window.orderOut(nil)
        callbacks.forEach { $0(style) }
        parent?.makeKeyAndOrderFront(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !model.isSaving, !model.isChoosing else { return false }
        guard model.confirmDiscard() else { return false }
        finish(nil)
        return false
    }
}

struct WorkshopView: View {
    @ObservedObject var model: WorkshopModel
    @State private var dropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("便签工坊", systemImage: "paintbrush.pointed")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button("关闭工坊", action: model.onCancel)
                    .keyboardShortcut(.cancelAction).disabled(model.isSaving || model.isChoosing)
                if model.isLoading || model.isSaving {
                    ProgressView().controlSize(.small)
                    Text(model.isSaving ? "正在保存…" : "正在读取图片…").font(.caption)
                }
                Button(action: model.chooseImage) { Label("上传底图", systemImage: "photo.badge.plus") }
                    .disabled(model.busy)
                Button(action: model.save) { Label("保存样式", systemImage: "checkmark") }
                    .buttonStyle(.borderedProminent).disabled(model.image == nil || model.busy)
            }.padding(16)
            Divider()
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("我的样式").font(.headline)
                        Spacer()
                        Button { model.select(nil) } label: { Image(systemName: "plus") }
                            .help("新建样式")
                    }.padding(.horizontal, 12).padding(.top, 14)
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(model.styles) { style in
                                Button { model.select(style) } label: {
                                    HStack(spacing: 8) {
                                        if let image = model.store.image(for: style) {
                                            Image(nsImage: image).resizable().scaledToFit().frame(width: 42, height: 38)
                                        }
                                        Text(style.name).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                                    }.padding(8)
                                        .background(model.draft.id == style.id ? Color.accentColor.opacity(0.14) : Color.clear)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                }.buttonStyle(.plain)
                            }
                        }.padding(.horizontal, 6)
                    }
                    if model.styles.isEmpty {
                        Text("暂无自定义样式").font(.caption).foregroundStyle(.secondary).padding(12)
                    }
                    Spacer(minLength: 0)
                    Button(role: .destructive, action: model.archive) { Label("移除样式", systemImage: "trash") }
                        .disabled(!model.styles.contains { $0.id == model.draft.id })
                        .padding(12)
                }.frame(width: 185).disabled(model.isSaving || model.isChoosing)
                Divider()
                VStack(spacing: 14) {
                    Picker("编辑模式", selection: $model.mode) {
                        Label("文字区域", systemImage: "text.viewfinder").tag("text")
                        Label("夹子位置", systemImage: "pin").tag("clip")
                        Label("悬挂预览", systemImage: "eye").tag("preview")
                    }.pickerStyle(.segmented)
                    WorkshopCanvas(model: model)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(dropTargeted ? Color.accentColor : Color.secondary.opacity(0.2)))
                        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $dropTargeted) { providers in
                            model.drop(providers)
                        }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("预览文字").font(.caption).foregroundStyle(.secondary)
                        WorkshopTextEditor(text: $model.sample).frame(height: 68)
                    }
                    if let message = model.message {
                        Text(message).font(.caption).foregroundStyle(model.isError ? Color.red : Color.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.padding(18).disabled(model.isSaving || model.isChoosing)
                Divider()
                settings.frame(width: 220).padding(16).disabled(model.isSaving || model.isChoosing)
            }
        }.frame(minWidth: 900, minHeight: 580)
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("样式设置").font(.headline)
            VStack(alignment: .leading, spacing: 6) {
                Text("名称").font(.caption).foregroundStyle(.secondary)
                TextField("我的便签", text: $model.draft.name).textFieldStyle(.roundedBorder)
            }
            ColorPicker("文字颜色", selection: Binding(get: { Color(nsColor: model.draft.color) }, set: { color in
                guard let rgb = NSColor(color).usingColorSpace(.deviceRGB) else { return }
                model.draft.red = rgb.redComponent; model.draft.green = rgb.greenComponent; model.draft.blue = rgb.blueComponent
            }), supportsOpacity: false)
            VStack(alignment: .leading, spacing: 6) {
                Text("最大字号  \(model.draft.fontSize, specifier: "%.1f")")
                Slider(value: $model.draft.fontSize, in: 8.5...22, step: 0.5)
            }
            Picker("文字对齐", selection: $model.draft.alignment) {
                Image(systemName: "text.alignleft").tag("left")
                Image(systemName: "text.aligncenter").tag("center")
                Image(systemName: "text.alignright").tag("right")
            }.pickerStyle(.segmented)
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text("悬挂角度  \(model.draft.tilt, specifier: "%.0f")°")
                Slider(value: Binding(get: { model.draft.tilt }, set: {
                    model.draft.tilt = $0
                    model.mode = "preview"
                }), in: -30...30, step: 1)
                Text("调整角度时自动展示上绳效果")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button {
                model.draft.textX = 0.22; model.draft.textY = 0.35
                model.draft.textWidth = 0.56; model.draft.textHeight = 0.45
                model.draft.clipX = 0.5; model.draft.clipY = 0.06; model.draft.tilt = 0
            } label: { Label("重置位置", systemImage: "arrow.counterclockwise") }
            Spacer()
        }.font(.system(size: 12))
    }
}

private struct WorkshopCanvas: View {
    @ObservedObject var model: WorkshopModel
    @State private var dragOrigin: CGPoint?
    @State private var resizeOrigin: CGSize?

    var body: some View {
        GeometryReader { geo in
            let width = min(geo.size.width - 40, (geo.size.height - 60) * 140 / 104)
            let height = width * 104 / 140
            if model.image == nil {
                Button(action: model.chooseImage) {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.badge.plus").font(.system(size: 34))
                        Text("选择便签底图")
                        Text(CustomStyleStore.importFormatHint)
                            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                }.buttonStyle(.plain).disabled(model.busy)
            } else if model.mode == "preview" {
                WorkshopHangingPreview(image: model.preview, style: model.draft)
            } else {
                ZStack(alignment: .topLeading) {
                    Image(nsImage: model.preview).resizable().frame(width: width, height: height)
                    if model.mode == "text" {
                        Rectangle().fill(Color.accentColor.opacity(0.08))
                            .overlay(Rectangle().stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3])))
                            .frame(width: model.draft.textWidth * width, height: model.draft.textHeight * height)
                            .offset(x: model.draft.textX * width, y: model.draft.textY * height)
                            .gesture(DragGesture().onChanged { value in
                                if dragOrigin == nil { dragOrigin = CGPoint(x: model.draft.textX, y: model.draft.textY) }
                                guard let origin = dragOrigin else { return }
                                model.draft.textX = min(1 - model.draft.textWidth, max(0, origin.x + value.translation.width / width))
                                model.draft.textY = min(1 - model.draft.textHeight, max(0, origin.y + value.translation.height / height))
                            }.onEnded { _ in dragOrigin = nil })
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                            .frame(width: 22, height: 22).background(Color.accentColor).clipShape(Circle())
                            .position(x: (model.draft.textX + model.draft.textWidth) * width,
                                      y: (model.draft.textY + model.draft.textHeight) * height)
                            .gesture(DragGesture().onChanged { value in
                                if resizeOrigin == nil { resizeOrigin = CGSize(width: model.draft.textWidth, height: model.draft.textHeight) }
                                guard let origin = resizeOrigin else { return }
                                model.draft.textWidth = min(1 - model.draft.textX, max(0.12, origin.width + value.translation.width / width))
                                model.draft.textHeight = min(1 - model.draft.textY, max(0.12, origin.height + value.translation.height / height))
                            }.onEnded { _ in resizeOrigin = nil })
                    }
                    if model.mode != "text" {
                        Clothespin().scaleEffect(1.2)
                            .frame(width: 36, height: 36)
                            .position(x: model.draft.clipX * width, y: model.draft.clipY * height)
                    }
                    if model.mode == "clip" {
                        Rectangle().fill(Color.clear)
                            .frame(width: width, height: height)
                            .contentShape(Rectangle())
                            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("artwork")).onChanged { value in
                                model.draft.clipX = min(1, max(0, value.location.x / width))
                                model.draft.clipY = min(1, max(0, value.location.y / height))
                            })
                    }
                }.frame(width: width, height: height)
                    .coordinateSpace(name: "artwork")
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
        }
    }
}

// Fit the rotated note AND its clip in the available canvas. This uses the
// same offsets and pivot as PeggedView, so the preview matches the real line.
struct NoteHangingGeometry {
    let size: CGSize
    let clip: CGPoint
    let tilt: Double
    var horizontalOffset: CGFloat { size.width * (0.5 - clip.x) }
    var verticalOffset: CGFloat { -size.height * clip.y }
    var groupHeight: CGFloat { size.height + PeggedView.cardOffsetBelowTop }
    var bounds: CGRect {
        let artwork = CGRect(x: -size.width * clip.x,
                             y: PeggedView.cardOffsetBelowTop - size.height * clip.y,
                             width: size.width, height: size.height)
        let pin = CGRect(x: -4.5, y: 0, width: 9, height: 26)
        let rotation = CGAffineTransform(rotationAngle: tilt * .pi / 180)
        return artwork.applying(rotation).union(pin.applying(rotation))
    }
    func fitted(in canvas: CGSize) -> (scale: CGFloat, pivot: CGPoint) {
        let box = bounds
        let scale = max(0.01, min(4.5, (canvas.width - 64) / box.width, (canvas.height - 64) / box.height))
        return (scale, CGPoint(x: canvas.width / 2 - box.midX * scale,
                              y: canvas.height / 2 - box.midY * scale))
    }
}

struct WorkshopHangingPreview: View {
    let image: NSImage
    let style: CustomNoteStyle
    var body: some View {
        GeometryReader { geo in
            let size = PeggedView.photoSize(for: image.size)
            let layout = NoteHangingGeometry(size: size, clip: CGPoint(x: style.clipX, y: style.clipY), tilt: style.tilt)
            let fit = layout.fitted(in: geo.size)
            ZStack(alignment: .topLeading) {
                Path { path in
                    let y = fit.pivot.y + Layout.pinAbove * fit.scale
                    path.move(to: CGPoint(x: 18, y: y))
                    path.addLine(to: CGPoint(x: geo.size.width - 18, y: y))
                }.stroke(Color.secondary.opacity(0.45), lineWidth: 1)
                VStack(spacing: -12) {
                    Clothespin().zIndex(1)
                    Image(nsImage: image).resizable().interpolation(.high)
                        .frame(width: size.width, height: size.height)
                        .offset(x: layout.horizontalOffset, y: layout.verticalOffset)
                }
                .frame(width: size.width, height: layout.groupHeight)
                .rotationEffect(.degrees(style.tilt), anchor: .top)
                .scaleEffect(fit.scale, anchor: .top)
                .position(x: fit.pivot.x, y: fit.pivot.y + layout.groupHeight / 2)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .accessibilityLabel("悬挂预览，角度 \(Int(style.tilt)) 度，夹子固定在选定位置")
        }
    }
}

private struct WorkshopTextEditor: NSViewRepresentable {
    @Binding var text: String
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let editor = PasteAwareTextView(frame: .zero)
        editor.isRichText = false
        editor.font = .systemFont(ofSize: 13)
        editor.textContainerInset = NSSize(width: 8, height: 8)
        editor.isVerticallyResizable = true
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.delegate = context.coordinator
        editor.string = text
        scroll.documentView = editor
        return scroll
    }
    func updateNSView(_ view: NSScrollView, context: Context) {
        context.coordinator.parent = self
        if let editor = view.documentView as? NSTextView, editor.string != text { editor.string = text }
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: WorkshopTextEditor
        init(parent: WorkshopTextEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            parent.text = editor.string
        }
    }
}
