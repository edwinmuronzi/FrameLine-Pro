import SwiftUI

struct DemoHarborScene: View {
    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.49, green: 0.71, blue: 0.86),
                        Color(red: 0.73, green: 0.86, blue: 0.95),
                        Color(red: 0.86, green: 0.91, blue: 0.86)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                water(in: size)
                sand(in: size)
                shore(in: size)
                skyline(in: size)
                operaHouse(in: size)
                figure(in: size)
                canopy(in: size)
            }
        }
    }

    private func water(in size: CGSize) -> some View {
        Path { path in
            path.addRect(CGRect(x: 0, y: size.height * 0.50, width: size.width, height: size.height * 0.22))
        }
        .fill(
            LinearGradient(
                colors: [Color(red: 0.36, green: 0.62, blue: 0.78), Color(red: 0.16, green: 0.38, blue: 0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func sand(in size: CGSize) -> some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: size.height * 0.70))
            path.addQuadCurve(
                to: CGPoint(x: size.width, y: size.height * 0.72),
                control: CGPoint(x: size.width * 0.5, y: size.height * 0.66)
            )
            path.addLine(to: CGPoint(x: size.width, y: size.height * 0.86))
            path.addLine(to: CGPoint(x: 0, y: size.height * 0.84))
            path.closeSubpath()
        }
        .fill(Color(red: 0.76, green: 0.64, blue: 0.46))
    }

    private func shore(in size: CGSize) -> some View {
        LinearGradient(
            colors: [Color(red: 0.22, green: 0.16, blue: 0.11), Color(red: 0.05, green: 0.04, blue: 0.03)],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: size.height * 0.2)
        .position(x: size.width / 2, y: size.height * 0.9)
    }

    private func skyline(in size: CGSize) -> some View {
        let heights: [CGFloat] = [0.16, 0.22, 0.13, 0.28, 0.18, 0.24, 0.12, 0.2]
        return HStack(alignment: .bottom, spacing: size.width * 0.012) {
            ForEach(Array(heights.enumerated()), id: \.offset) { index, height in
                RoundedRectangle(cornerRadius: 1)
                    .fill(index % 3 == 0 ? Color(red: 0.55, green: 0.62, blue: 0.68) : Color(red: 0.32, green: 0.38, blue: 0.44))
                    .frame(width: size.width * 0.035, height: size.height * height)
            }
        }
        .position(x: size.width * 0.74, y: size.height * 0.42)
    }

    private func operaHouse(in size: CGSize) -> some View {
        ZStack {
            sail(width: size.width * 0.09, height: size.height * 0.09)
                .offset(x: -size.width * 0.05)
            sail(width: size.width * 0.11, height: size.height * 0.12)
            sail(width: size.width * 0.08, height: size.height * 0.08)
                .offset(x: size.width * 0.055)
        }
        .position(x: size.width * 0.42, y: size.height * 0.46)
    }

    private func sail(width: CGFloat, height: CGFloat) -> some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: height))
            path.addQuadCurve(to: CGPoint(x: width, y: height), control: CGPoint(x: width * 0.5, y: -height * 0.15))
            path.closeSubpath()
        }
        .fill(Color(red: 0.95, green: 0.94, blue: 0.9))
        .frame(width: width, height: height)
    }

    private func figure(in size: CGSize) -> some View {
        Capsule()
            .fill(Color.black.opacity(0.78))
            .frame(width: size.width * 0.012, height: size.height * 0.035)
            .position(x: size.width * 0.48, y: size.height * 0.74)
    }

    private func canopy(in size: CGSize) -> some View {
        ZStack {
            ForEach(0..<9, id: \.self) { index in
                Ellipse()
                    .fill(Color(red: 0.05, green: 0.1, blue: 0.05).opacity(0.92))
                    .frame(width: size.width * 0.42, height: size.height * 0.22)
                    .position(
                        x: size.width * (0.05 + CGFloat(index) * 0.13),
                        y: size.height * (index.isMultiple(of: 2) ? 0.08 : 0.14)
                    )
            }
            ForEach(0..<6, id: \.self) { index in
                Capsule()
                    .fill(Color(red: 0.08, green: 0.14, blue: 0.07))
                    .frame(width: size.width * 0.28, height: size.height * 0.045)
                    .rotationEffect(.degrees(Double(index * 18 - 40)))
                    .position(x: size.width * (0.15 + CGFloat(index) * 0.15), y: size.height * 0.16)
            }
        }
    }
}
