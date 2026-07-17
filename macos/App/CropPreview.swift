import SwiftUI
import AppKit
import ForgeCore

/// Shows a source image with the region that will be **kept** highlighted and
/// everything that will be cropped away dimmed. Pure visual aid — the geometry
/// comes from `CropGeometry.keptRegion`, the same math the exporter uses.
struct CropPreview: View {
    let image: NSImage
    let target: PixelSize

    var body: some View {
        GeometryReader { geo in
            let fitted = fittedRect(imageSize: image.size, in: geo.size)
            let region = CropGeometry.keptRegion(
                source: PixelSize(width: Int(image.size.width.rounded()),
                                  height: Int(image.size.height.rounded())),
                target: target
            )
            let keep = CGRect(
                x: fitted.minX + region.x * fitted.width,
                y: fitted.minY + region.y * fitted.height,
                width: region.width * fitted.width,
                height: region.height * fitted.height
            )

            ZStack(alignment: .topLeading) {
                Image(nsImage: image)
                    .resizable()
                    .frame(width: fitted.width, height: fitted.height)
                    .position(x: fitted.midX, y: fitted.midY)

                // Dim the four bands around the kept region (a zero-size band
                // simply draws nothing, so an un-cropped axis is fine).
                dimBand(CGRect(x: fitted.minX, y: fitted.minY,
                               width: fitted.width, height: keep.minY - fitted.minY))
                dimBand(CGRect(x: fitted.minX, y: keep.maxY,
                               width: fitted.width, height: fitted.maxY - keep.maxY))
                dimBand(CGRect(x: fitted.minX, y: keep.minY,
                               width: keep.minX - fitted.minX, height: keep.height))
                dimBand(CGRect(x: keep.maxX, y: keep.minY,
                               width: fitted.maxX - keep.maxX, height: keep.height))

                Rectangle()
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .frame(width: keep.width, height: keep.height)
                    .position(x: keep.midX, y: keep.midY)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private func dimBand(_ rect: CGRect) -> some View {
        Rectangle()
            .fill(Color.black.opacity(0.55))
            .frame(width: max(0, rect.width), height: max(0, rect.height))
            .position(x: rect.midX, y: rect.midY)
    }

    private func fittedRect(imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let w = imageSize.width * scale
        let h = imageSize.height * scale
        return CGRect(x: (container.width - w) / 2, y: (container.height - h) / 2, width: w, height: h)
    }
}
