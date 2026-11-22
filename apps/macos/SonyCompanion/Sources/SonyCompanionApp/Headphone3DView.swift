import SwiftUI
import SceneKit
import simd
import QuartzCore

#if os(macOS)
private typealias PlatformColor = NSColor
#else
private typealias PlatformColor = UIColor
#endif

/// A real-time 3D model of the connected headphone.
///
/// Built procedurally from SceneKit primitives — no downloaded model and no
/// product photography — so every supported model gets a real object without
/// shipping anyone else's assets. The object turns with the pointer on a Mac
/// and with drag on iOS, on top of a slow idle drift, so it reads as a physical
/// thing rather than a picture.
///
/// Form factor follows the model name: over-ear for WH-/MDR-, buds for WF-.
struct Headphone3DView: View {
    let model: String
    var tint: Color = .accentColor
    /// The colour the user picked; the headphones do not report their finish.
    var finish: HeadphoneFinish = .black

    @State private var parallax: CGPoint = .zero

    var body: some View {
        SceneKitSurface(model: model, tint: tint, finish: finish, parallax: parallax)
            .id(finish)
            #if os(macOS)
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    withAnimation(.smooth(duration: 0.35)) {
                        parallax = CGPoint(x: point.x, y: point.y)
                    }
                case .ended:
                    withAnimation(.smooth(duration: 0.6)) { parallax = .zero }
                }
            }
            #endif
            // Simultaneous so a drag still scrolls the page underneath.
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        parallax = CGPoint(x: value.location.x, y: value.location.y)
                    }
                    .onEnded { _ in
                        withAnimation(.smooth(duration: 0.6)) { parallax = .zero }
                    }
            )
            .accessibilityHidden(true)
    }
}

// MARK: - Platform bridge

#if os(macOS)
private struct SceneKitSurface: NSViewRepresentable {
    let model: String
    let tint: Color
    let finish: HeadphoneFinish
    let parallax: CGPoint

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.isPlaying = true
        view.rendersContinuously = true
        context.coordinator.attach(to: view, model: model, tint: tint, finish: finish)
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        context.coordinator.setParallax(parallax, in: view)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        private let rig = HeadphoneRig()
        func attach(to view: SCNView, model: String, tint: Color, finish: HeadphoneFinish) {
            rig.build(model: model, tint: tint, finish: finish)
            view.scene = rig.scene
            view.pointOfView = rig.cameraNode
        }
        func setParallax(_ point: CGPoint, in view: SCNView) { rig.setParallax(point, in: view) }
    }
}
#else
private struct SceneKitSurface: UIViewRepresentable {
    let model: String
    let tint: Color
    let finish: HeadphoneFinish
    let parallax: CGPoint

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.isPlaying = true
        view.rendersContinuously = true
        context.coordinator.attach(to: view, model: model, tint: tint, finish: finish)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.setParallax(parallax, in: view)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        private let rig = HeadphoneRig()
        func attach(to view: SCNView, model: String, tint: Color, finish: HeadphoneFinish) {
            rig.build(model: model, tint: tint, finish: finish)
            view.scene = rig.scene
            view.pointOfView = rig.cameraNode
        }
        func setParallax(_ point: CGPoint, in view: SCNView) { rig.setParallax(point, in: view) }
    }
}
#endif

// MARK: - Finish

/// Generic colourways. Named by colour only; no product branding.
enum HeadphoneFinish: String, CaseIterable, Identifiable {
    case black, silver, midnightBlue

    var id: String { rawValue }

    var title: String {
        switch self {
        case .black: return "Black"
        case .silver: return "Silver"
        case .midnightBlue: return "Midnight Blue"
        }
    }

    /// Shell, cushion and slider colours as linear-ish RGB.
    fileprivate var palette: (shell: PlatformColor, cushion: PlatformColor, metal: PlatformColor) {
        switch self {
        case .black:
            return (PlatformColor(white: 0.06, alpha: 1),
                    PlatformColor(white: 0.055, alpha: 1),
                    PlatformColor(white: 0.30, alpha: 1))
        case .silver:
            return (PlatformColor(red: 0.58, green: 0.57, blue: 0.55, alpha: 1),
                    PlatformColor(red: 0.47, green: 0.46, blue: 0.44, alpha: 1),
                    PlatformColor(red: 0.70, green: 0.70, blue: 0.69, alpha: 1))
        case .midnightBlue:
            return (PlatformColor(red: 0.12, green: 0.16, blue: 0.26, alpha: 1),
                    PlatformColor(red: 0.09, green: 0.11, blue: 0.17, alpha: 1),
                    PlatformColor(red: 0.36, green: 0.40, blue: 0.48, alpha: 1))
        }
    }
}

// MARK: - Rig

final class HeadphoneRig {
    let scene = SCNScene()
    let cameraNode = SCNNode()

    /// Turns with the pointer. The idle drift lives on a child, so the two
    /// motions never fight over the same transform.
    private let pivot = SCNNode()
    private let modelRoot = SCNNode()

    private var built = false

    private var finish: HeadphoneFinish = .black

    func build(model: String, tint: Color, finish: HeadphoneFinish = .black) {
        self.finish = finish
        guard !built else { return }
        built = true

        scene.rootNode.addChildNode(pivot)
        pivot.addChildNode(modelRoot)

        let upper = model.uppercased()
        let isBuds = upper.contains("WF-") || upper.contains("BUD") || upper.contains("SP800")
        let accent = platformColor(tint)
        if isBuds {
            buildBuds(accent: accent)
        } else {
            buildOverEar(accent: accent)
        }

        buildCamera()
        buildLights()
        buildEnvironment()
        startIdle()
    }

    // MARK: Materials

    private func platformColor(_ color: Color) -> PlatformColor {
        #if os(macOS)
        return NSColor(color)
        #else
        return UIColor(color)
        #endif
    }

    private func material(
        _ color: PlatformColor,
        metalness: CGFloat,
        roughness: CGFloat,
        clearcoat: CGFloat = 0
    ) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.metalness.contents = metalness
        m.roughness.contents = roughness
        if clearcoat > 0 {
            m.clearCoat.contents = clearcoat
            m.clearCoatRoughness.contents = 0.18
        }
        return m
    }

    // MARK: Geometry

    // Over-ear geometry, in scene units (≈ 10 cm). Proportions follow a
    // modern closed-back over-ear: slim flat band, short slider arms, tall
    // rounded-oval cups with a domed outer face. Built as custom meshes so the
    // surfaces are continuous; no imported model and no product artwork.
    private enum OverEar {
        static let cupCentreX: Float = 1.40
        static let cupCentreY: Float = -0.30
        static let cupHalfHeight: Float = 0.93
        static let cupHalfDepth: Float = 0.64
        static let cupDepth: Float = 0.40      // inner face to outer rim
        static let bandRadiusX: Float = 1.40
        static let bandRadiusY: Float = 1.22
        static let bandBaseY: Float = 0.96
    }

    private func buildOverEar(accent _: PlatformColor) {
        let colours = finish.palette
        // Soft-touch plastic: no metalness, fairly rough, a thin clear coat
        // for the sheen along the edges.
        let shell = material(colours.shell, metalness: 0, roughness: 0.58, clearcoat: 0.12)
        let cushion = material(colours.cushion, metalness: 0, roughness: 0.92)
        let metal = material(colours.metal, metalness: 0.85, roughness: 0.32)
        let fabric = material(PlatformColor(white: 0.04, alpha: 1), metalness: 0, roughness: 1)
        let button = material(colours.shell, metalness: 0, roughness: 0.4, clearcoat: 0.5)

        modelRoot.addChildNode(headband(shell: shell, pad: cushion))

        for side: Float in [-1, 1] {
            // Each side hangs from a node at the cup centre, tilted so the
            // tops lean in as they would on a head.
            let hanger = SCNNode()
            hanger.position = SCNVector3(side * OverEar.cupCentreX, OverEar.cupCentreY, 0)
            hanger.eulerAngles = SCNVector3(0, 0, side * 0.045)
            modelRoot.addChildNode(hanger)

            // The cup is built facing +x (outward); the left one is turned
            // half a revolution about y rather than mirrored, so normals and
            // winding stay correct.
            let cupSide = SCNNode()
            cupSide.eulerAngles = SCNVector3(0, side > 0 ? 0 : Float.pi, 0)
            hanger.addChildNode(cupSide)

            let inner: Float = -OverEar.cupDepth / 2
            let cup = SCNNode(geometry: cupShell(material: shell))
            cup.position = SCNVector3(inner, 0, 0)
            cupSide.addChildNode(cup)

            let pad = SCNNode(geometry: cushionRing(material: cushion))
            pad.position = SCNVector3(inner, 0, 0)
            cupSide.addChildNode(pad)

            // Dark fabric inside the cushion.
            let cloth = SCNNode(geometry: ovalDisc(scale: 0.70, material: fabric))
            cloth.position = SCNVector3(inner - 0.10, 0, 0)
            cupSide.addChildNode(cloth)

            // Slider arm and hinge above the cup.
            let top = OverEar.cupHalfHeight
            let hinge = SCNBox(width: 0.17, height: 0.11, length: 0.30, chamferRadius: 0.05)
            hinge.materials = [shell]
            let hingeNode = SCNNode(geometry: hinge)
            hingeNode.position = SCNVector3(0, top + 0.02, 0)
            hanger.addChildNode(hingeNode)

            let armLength: CGFloat = 0.50
            let arm = SCNBox(width: 0.055, height: armLength, length: 0.15, chamferRadius: 0.026)
            arm.materials = [metal]
            let armNode = SCNNode(geometry: arm)
            armNode.position = SCNVector3(0, top + 0.06 + Float(armLength) / 2, 0)
            hanger.addChildNode(armNode)

            if side < 0 {
                // Two buttons along the lower rear edge of the left cup.
                for (k, length) in [(0, 0.11), (1, 0.08)] as [(Int, CGFloat)] {
                    let b = SCNCapsule(capRadius: 0.026, height: length)
                    b.materials = [button]
                    let node = SCNNode(geometry: b)
                    let y = -0.42 - Float(k) * 0.20
                    node.position = SCNVector3(OverEar.cupDepth / 2 - 0.12, y, -OverEar.cupHalfDepth * 0.93)
                    node.eulerAngles = SCNVector3(0, 0, 0.35)
                    cupSide.addChildNode(node)
                }
            }
        }

        modelRoot.eulerAngles = SCNVector3(-0.10, 0.62, 0)
        modelRoot.position = SCNVector3(0, -0.10, 0)
    }

    // MARK: Over-ear parts

    /// Superellipse point in the cup's (y, z) plane, `n` controls squareness.
    private func oval(_ u: Float, scale: Float, n: Float = 2.6) -> (Float, Float) {
        let c = cos(u), s = sin(u)
        let y = OverEar.cupHalfHeight * scale * copysign(pow(abs(s), 2 / n), s)
        let z = OverEar.cupHalfDepth * scale * copysign(pow(abs(c), 2 / n), c)
        return (y, z)
    }

    /// The cup shell: rings along its axis from the flat inner face, up a
    /// short wall, round a fillet and across a shallow dome.
    private func cupShell(material: SCNMaterial) -> SCNGeometry {
        var profile: [(x: Float, s: Float)] = [(0, 0), (0, 0.55), (0, 0.97), (0.02, 1.0)]
        let wallEnd: Float = 0.24
        for k in 1...4 {
            let t = Float(k) / 4
            profile.append((0.02 + (wallEnd - 0.02) * t, 1.0 - 0.025 * t))
        }
        let r: Float = 0.14
        for k in 1...10 {
            let a = Float(k) / 10 * .pi / 2
            profile.append((wallEnd + r * sin(a), 0.975 - (r / 0.78) * (1 - cos(a))))
        }
        let rimX = wallEnd + r
        let rimS = profile.last!.s
        for k in 1...8 {
            let t = Float(k) / 8
            let sc = rimS * (1 - t)
            profile.append((rimX + 0.035 * (1 - (sc / rimS) * (sc / rimS)), sc))
        }

        let segments = 72
        var grid: [[SCNVector3]] = []
        var centres: [SCNVector3] = []
        for ring in profile {
            var row: [SCNVector3] = []
            for j in 0..<segments {
                let u = Float(j) / Float(segments) * 2 * .pi
                let (y, z) = oval(u, scale: max(ring.s, 0.0001))
                row.append(SCNVector3(ring.x, y, z))
            }
            grid.append(row)
            centres.append(SCNVector3(ring.x < 0.2 ? ring.x - 0.3 : ring.x - 0.3, 0, 0))
        }
        return gridGeometry(grid, centres: centres, wrapColumns: true, material: material)
    }

    /// A soft cushion swept round the inside of the cup rim.
    private func cushionRing(material: SCNMaterial) -> SCNGeometry {
        let around = 72, pipe = 20
        var grid: [[SCNVector3]] = []
        var centres: [SCNVector3] = []
        for j in 0..<around {
            let u = Float(j) / Float(around) * 2 * .pi
            let (y, z) = oval(u, scale: 0.85)
            let len = max(sqrt(y * y + z * z), 0.0001)
            let ry = y / len, rz = z / len
            let centre = SCNVector3(-0.10, y, z)
            var row: [SCNVector3] = []
            for k in 0..<pipe {
                let v = Float(k) / Float(pipe) * 2 * .pi
                let radial = 0.125 * cos(v)
                let axial = 0.10 * sin(v)
                row.append(SCNVector3(-0.10 + axial, y + ry * radial, z + rz * radial))
            }
            grid.append(row)
            centres.append(centre)
        }
        return gridGeometry(grid, centres: centres, wrapColumns: true, wrapRows: true, material: material)
    }

    private func ovalDisc(scale: Float, material: SCNMaterial) -> SCNGeometry {
        let segments = 48
        var rows: [[SCNVector3]] = [Array(repeating: SCNVector3(0, 0, 0), count: segments)]
        rows.append((0..<segments).map { j in
            let (y, z) = oval(Float(j) / Float(segments) * 2 * .pi, scale: scale)
            return SCNVector3(0, y, z)
        })
        let g = gridGeometry(rows, centres: [SCNVector3(0.5, 0, 0), SCNVector3(0.5, 0, 0)],
                             wrapColumns: true, material: material)
        material.isDoubleSided = true
        return g
    }

    /// The band: a flat, rounded section swept along an elliptical arch,
    /// narrowing toward the ends, with a padded strip underneath.
    private func headband(shell: SCNMaterial, pad: SCNMaterial) -> SCNNode {
        let node = SCNNode()
        node.addChildNode(SCNNode(geometry: bandSweep(
            from: 0.035, to: 0.965, thickness: 0.055, width: 0.17, taper: 0.22, inset: 0, material: shell)))
        node.addChildNode(SCNNode(geometry: bandSweep(
            from: 0.16, to: 0.84, thickness: 0.035, width: 0.13, taper: 0.85, inset: 0.06, material: pad)))
        // End housings close the band and hold the slider arms.
        for side: Float in [-1, 1] {
            let housing = SCNBox(width: 0.13, height: 0.26, length: 0.36, chamferRadius: 0.06)
            housing.materials = [shell]
            let h = SCNNode(geometry: housing)
            h.position = SCNVector3(side * 1.395, 1.06, 0)
            h.eulerAngles = SCNVector3(0, 0, side * 0.06)
            node.addChildNode(h)
        }
        return node
    }

    private func bandSweep(
        from: Float, to: Float, thickness: Float, width: Float,
        taper: Float, inset: Float, material: SCNMaterial
    ) -> SCNGeometry {
        let steps = 90, section = 28
        var grid: [[SCNVector3]] = []
        var centres: [SCNVector3] = []
        for i in 0...steps {
            let t = Float(i) / Float(steps)
            let phi = Float.pi * (from + (to - from) * t)
            let cx = OverEar.bandRadiusX * cos(phi)
            let cy = OverEar.bandBaseY + OverEar.bandRadiusY * sin(phi)
            // Inward normal of the ellipse at phi.
            var nx = -cos(phi) / OverEar.bandRadiusX
            var ny = -sin(phi) / OverEar.bandRadiusY
            let nl = sqrt(nx * nx + ny * ny)
            nx /= nl; ny /= nl
            let ox = cx + nx * inset, oy = cy + ny * inset
            // Narrower toward the ends.
            let edge = min(t, 1 - t) * 2
            let w = width * (1 - taper * (1 - edge))
            var row: [SCNVector3] = []
            for k in 0..<section {
                let v = Float(k) / Float(section) * 2 * .pi
                // Rounded rectangle via a squarish superellipse.
                let a = copysign(pow(abs(cos(v)), 0.5), cos(v))
                let b = copysign(pow(abs(sin(v)), 0.5), sin(v))
                row.append(SCNVector3(ox + nx * thickness * a, oy + ny * thickness * a, w * b))
            }
            grid.append(row)
            centres.append(SCNVector3(ox, oy, 0))
        }
        return gridGeometry(grid, centres: centres, wrapColumns: true, material: material)
    }

    /// Triangulates a grid of points (rows × columns) with smooth normals,
    /// oriented away from each row's centre so lighting is never inverted.
    private func gridGeometry(
        _ grid: [[SCNVector3]],
        centres: [SCNVector3],
        wrapColumns: Bool,
        wrapRows: Bool = false,
        material: SCNMaterial
    ) -> SCNGeometry {
        let rows = grid.count, cols = grid.first?.count ?? 0
        var positions: [SIMD3<Float>] = []
        positions.reserveCapacity(rows * cols)
        for row in grid { for p in row { positions.append(SIMD3(Float(p.x), Float(p.y), Float(p.z))) } }

        var indices: [UInt32] = []
        let rowSpan = wrapRows ? rows : rows - 1
        let colSpan = wrapColumns ? cols : cols - 1
        for i in 0..<rowSpan {
            for j in 0..<colSpan {
                let a = UInt32(i * cols + j)
                let b = UInt32(i * cols + (j + 1) % cols)
                let c = UInt32(((i + 1) % rows) * cols + j)
                let d = UInt32(((i + 1) % rows) * cols + (j + 1) % cols)
                indices += [a, c, b, b, c, d]
            }
        }

        var normals = Array(repeating: SIMD3<Float>(0, 0, 0), count: positions.count)
        for t in stride(from: 0, to: indices.count, by: 3) {
            let i0 = Int(indices[t]), i1 = Int(indices[t + 1]), i2 = Int(indices[t + 2])
            let n = simd_cross(positions[i1] - positions[i0], positions[i2] - positions[i0])
            normals[i0] += n; normals[i1] += n; normals[i2] += n
        }
        // Orient: count how many normals point away from their row centre.
        var outward = 0
        for (idx, n) in normals.enumerated() {
            let c = centres[idx / cols]
            let d = positions[idx] - SIMD3(Float(c.x), Float(c.y), Float(c.z))
            if simd_dot(n, d) >= 0 { outward += 1 }
        }
        let flip = outward < normals.count / 2
        if flip {
            for t in stride(from: 0, to: indices.count, by: 3) { indices.swapAt(t + 1, t + 2) }
        }
        let finalNormals = normals.map { n -> SCNVector3 in
            let len = simd_length(n)
            let u = len > 0 ? n / len : SIMD3<Float>(0, 1, 0)
            let o = flip ? -u : u
            return SCNVector3(o.x, o.y, o.z)
        }
        let vertexSource = SCNGeometrySource(vertices: positions.map { SCNVector3($0.x, $0.y, $0.z) })
        let normalSource = SCNGeometrySource(normals: finalNormals)
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        let geometry = SCNGeometry(sources: [vertexSource, normalSource], elements: [element])
        geometry.materials = [material]
        return geometry
    }

    /// True wireless buds: a rounded bean with a flat outer face and a soft
    /// tip, no stem.
    private func buildBuds(accent _: PlatformColor) {
        let colours = finish.palette
        let shell = material(colours.shell, metalness: 0, roughness: 0.45, clearcoat: 0.4)
        let face = material(colours.shell, metalness: 0, roughness: 0.25, clearcoat: 0.8)
        let tip = material(colours.cushion, metalness: 0, roughness: 0.9)

        for side: Float in [-1, 1] {
            let bud = SCNNode()
            bud.position = SCNVector3(side * 0.78, 0.30, 0)
            bud.eulerAngles = SCNVector3(0, side * 0.35, side * -0.25)
            modelRoot.addChildNode(bud)

            let body = SCNSphere(radius: 0.5)
            body.segmentCount = 64
            body.materials = [shell]
            let bodyNode = SCNNode(geometry: body)
            bodyNode.scale = SCNVector3(0.80, 1.0, 0.86)
            bud.addChildNode(bodyNode)

            // Flat touch surface on the outer side.
            let disc = SCNCylinder(radius: 0.34, height: 0.04)
            disc.materials = [face]
            let discNode = SCNNode(geometry: disc)
            discNode.position = SCNVector3(side * 0.37, 0.02, 0)
            discNode.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
            discNode.scale = SCNVector3(1.0, 1.0, 1.1)
            bud.addChildNode(discNode)

            let ear = SCNSphere(radius: 0.21)
            ear.segmentCount = 40
            ear.materials = [tip]
            let earNode = SCNNode(geometry: ear)
            earNode.position = SCNVector3(-side * 0.40, -0.06, 0.10)
            earNode.scale = SCNVector3(0.9, 1.0, 1.0)
            bud.addChildNode(earNode)
        }

        modelRoot.eulerAngles = SCNVector3(-0.08, 0.30, 0)
    }

    /// A tube swept along an arc, built from overlapping spheres so it needs no
    /// platform-specific path type and no custom mesh.
    private func arcBand(
        radius: CGFloat,
        thickness: CGFloat,
        from: CGFloat,
        to: CGFloat,
        segments: Int,
        material: SCNMaterial
    ) -> SCNNode {
        let container = SCNNode()
        let sphere = SCNSphere(radius: thickness)
        sphere.segmentCount = 16
        sphere.materials = [material]

        for i in 0...segments {
            let t = CGFloat(i) / CGFloat(segments)
            let angle = CGFloat.pi * (from + (to - from) * t)
            let node = SCNNode(geometry: sphere)
            node.position = SCNVector3(
                Float(cos(angle) * radius),
                Float(sin(angle) * radius),
                0
            )
            // Slightly flattened front-to-back, like a real headband.
            node.scale = SCNVector3(1.0, 1.0, 0.74)
            container.addChildNode(node)
        }
        return container
    }

    // MARK: Camera, lights, environment

    private func buildCamera() {
        let camera = SCNCamera()
        camera.fieldOfView = 34
        camera.zNear = 0.1
        camera.zFar = 100
        camera.wantsHDR = true
        camera.bloomIntensity = 0.0
        camera.bloomThreshold = 0.95
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0.45, 6.6)
        cameraNode.look(at: SCNVector3(0, 0.30, 0), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        scene.rootNode.addChildNode(cameraNode)
    }

    private func buildLights() {
        let key = SCNLight()
        key.type = .omni
        key.intensity = 520
        key.temperature = 5600
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.position = SCNVector3(3.2, 3.6, 4.4)
        scene.rootNode.addChildNode(keyNode)

        let fill = SCNLight()
        fill.type = .omni
        fill.intensity = 200
        fill.temperature = 6800
        let fillNode = SCNNode()
        fillNode.light = fill
        fillNode.position = SCNVector3(-4.0, 0.4, 3.0)
        scene.rootNode.addChildNode(fillNode)

        let rim = SCNLight()
        rim.type = .directional
        rim.intensity = 380
        rim.temperature = 5200
        let rimNode = SCNNode()
        rimNode.light = rim
        rimNode.eulerAngles = SCNVector3(-0.5, Float.pi * 0.85, 0)
        scene.rootNode.addChildNode(rimNode)

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 40
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)
    }

    /// A soft studio gradient for the metal to reflect. Generated with
    /// CoreGraphics so the same code runs on both platforms.
    private func buildEnvironment() {
        let width = 256, height = 256
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }

        let colors = [
            CGColor(gray: 1.0, alpha: 1.0),
            CGColor(gray: 0.34, alpha: 1.0),
            CGColor(gray: 0.05, alpha: 1.0),
        ] as CFArray
        if let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.55, 1]) {
            ctx.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: height),
                end: CGPoint(x: 0, y: 0),
                options: []
            )
        }
        ctx.setFillColor(CGColor(gray: 1.0, alpha: 0.85))
        ctx.fillEllipse(in: CGRect(x: 28, y: 150, width: 92, height: 62))
        ctx.setFillColor(CGColor(gray: 1.0, alpha: 0.32))
        ctx.fillEllipse(in: CGRect(x: 148, y: 38, width: 72, height: 42))

        if let image = ctx.makeImage() {
            scene.lightingEnvironment.contents = image
            // Matte finishes read their shape from reflections, so the
            // studio environment carries more of the light than before.
            scene.lightingEnvironment.intensity = 0.75
        }
    }

    // MARK: Motion

    private func startIdle() {
        let drift = SCNAction.repeatForever(
            .sequence([
                .rotateBy(x: 0.02, y: 0.05, z: 0, duration: 3.2),
                .rotateBy(x: -0.02, y: -0.05, z: 0, duration: 3.2),
            ])
        )
        drift.timingMode = .easeInEaseOut
        modelRoot.runAction(drift, forKey: "idle")

        let bob = SCNAction.repeatForever(
            .sequence([
                .moveBy(x: 0, y: 0.045, z: 0, duration: 2.6),
                .moveBy(x: 0, y: -0.045, z: 0, duration: 2.6),
            ])
        )
        bob.timingMode = .easeInEaseOut
        modelRoot.runAction(bob, forKey: "bob")
    }

    /// Rotates the pivot a few degrees toward the pointer. Small angles read as
    /// depth; large ones read as a spinning object.
    func setParallax(_ point: CGPoint, in view: SCNView) {
        let size = view.bounds.size
        guard size.width > 1, size.height > 1 else { return }
        let nx = max(-1, min(1, (point.x / size.width) * 2 - 1))
        let ny = max(-1, min(1, (point.y / size.height) * 2 - 1))

        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.30
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeOut)
        pivot.eulerAngles = SCNVector3(
            Float(-ny) * 0.14,
            Float(nx) * 0.26,
            0
        )
        SCNTransaction.commit()
    }
}
