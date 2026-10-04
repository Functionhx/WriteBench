import SwiftUI
import PencilKit

struct PadHandwriting: UIViewRepresentable {
    @Binding var data: Data?
    var erasing: Bool
    var editable: Bool
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> PKCanvasView {
        let view = PKCanvasView()
        view.delegate = context.coordinator
        view.drawingPolicy = .anyInput
        view.backgroundColor = .white
        view.layer.cornerRadius = 12
        view.accessibilityLabel = "手写答题纸"
        view.accessibilityIdentifier = "handwriting-canvas"
        return view
    }
    func updateUIView(_ view: PKCanvasView, context: Context) {
        context.coordinator.parent = self
        if data != context.coordinator.lastData {
            view.drawing = data.flatMap { try? PKDrawing(data: $0) } ?? PKDrawing()
            context.coordinator.lastData = data
        }
        view.isUserInteractionEnabled = editable
        view.tool = erasing ? PKEraserTool(.bitmap) : PKInkingTool(.pen, color: .black, width: 2.5)
    }
    static func dismantleUIView(_ uiView: PKCanvasView, coordinator: Coordinator) { uiView.delegate = nil }
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: PadHandwriting
        var lastData: Data?
        init(_ parent: PadHandwriting) { self.parent = parent }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            let data: Data? = canvasView.drawing.bounds.isEmpty ? nil : canvasView.drawing.dataRepresentation(); lastData = data; parent.data = data
        }
    }
}
