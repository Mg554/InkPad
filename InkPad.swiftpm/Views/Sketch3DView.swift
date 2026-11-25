import PencilKit
import SceneKit
import SwiftUI
import UIKit

/// Native, offline approximation of sketch-to-3D: the selected ink is
/// classified from its own geometry and shown as a rotatable solid. There is
/// no WebGL, mesh upload or network call — the sketch stays on this iPad.
enum SketchShape: String {
    case sphere, box, cylinder, cone

    var title: String {
        switch self {
        case .sphere: return "Sphere"
        case .box: return "Box"
        case .cylinder: return "Cylinder"
        case .cone: return "Cone"
        }
    }
}

enum Sketch3D {
    static func classify(_ drawing: PKDrawing) -> SketchShape {
        let bounds = drawing.bounds
        let ratio = bounds.width / max(bounds.height, 1)
        let points = drawing.strokes.flatMap { ShapeRecognizer.points(of: $0) }
        var closed = 0
        if let first = points.first, let last = points.last {
            let span = max(bounds.width, bounds.height, 1)
            closed = hypot(first.x - last.x, first.y - last.y) < span * 0.12 ? 1 : 0
        }
        if ratio > 0.78, ratio < 1.25, closed == 1 { return .sphere }
        if ratio < 0.6 { return .cylinder }
        if ratio > 1.7 { return .box }
        return .cone
    }
}

struct Sketch3DView: UIViewRepresentable {
    let shape: SketchShape

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.allowsCameraControl = true
        view.defaultCameraController.interactionMode = .orbitTurntable
        view.autoenablesDefaultLighting = true

        let scene = SCNScene()
        let node = SCNNode(geometry: geometry(for: shape))
        node.geometry?.firstMaterial?.diffuse.contents = UIColor.systemBlue.withAlphaComponent(0.85)
        node.geometry?.firstMaterial?.specular.contents = UIColor.white
        node.geometry?.firstMaterial?.shininess = 70
        scene.rootNode.addChildNode(node)

        let camera = SCNCamera()
        camera.zNear = 0.1
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 1.4, 4.2)
        cameraNode.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(cameraNode)

        view.scene = scene
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {}

    private func geometry(for shape: SketchShape) -> SCNGeometry {
        switch shape {
        case .sphere:
            return SCNSphere(radius: 1.1)
        case .box:
            return SCNBox(width: 2.2, height: 1.3, length: 1.2, chamferRadius: 0.06)
        case .cylinder:
            return SCNCylinder(radius: 0.8, height: 2.2)
        case .cone:
            return SCNCone(topRadius: 0.05, bottomRadius: 1, height: 2)
        }
    }
}

struct Sketch3DRequest: Identifiable {
    let id = UUID()
    let drawing: PKDrawing
}

struct Sketch3DSheet: View {
    @Environment(\.dismiss) private var dismiss
    let request: Sketch3DRequest

    private var drawing: PKDrawing { request.drawing }

    private var shape: SketchShape { Sketch3D.classify(drawing) }

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.lg) {
                Sketch3DView(shape: shape)
                    .frame(minHeight: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.quaternary))
                Text(trMessage("Read as a {}. Drag to turn it.").replacingOccurrences(of: "{}", with: tr(shape.title)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding()
            .navigationTitle(tr("Sketch to 3D"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr("Done")) { dismiss() }
                }
            }
        }
    }
}
