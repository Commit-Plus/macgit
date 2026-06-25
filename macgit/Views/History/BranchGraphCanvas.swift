//
//  BranchGraphCanvas.swift
//  macgit
//

import SwiftUI

struct BranchGraphCanvas: View {
    let model: SourceGit.CommitGraphModel

    let rowHeight: CGFloat = 24
    let laneWidth: CGFloat = 14
    let dotSize: CGFloat = 8
    let graphTrailingPadding: CGFloat = 8

    init(model: SourceGit.CommitGraphModel) {
        self.model = model
    }

    /// Temporary compatibility initializer while HistoryView still uses the
    /// legacy graph model. Removed when the integration task switches it to
    /// CommitGraphGenerator.
    init(nodes: [GraphNode], paths: [GraphPath], laneCount: Int) {
        let convertedPaths = paths.map { path in
            SourceGit.GraphPath(
                points: path.points.map {
                    CGPoint(
                        x: 10 + Double($0.lane) * 12,
                        y: Double($0.row) + 0.5
                    )
                },
                colorIndex: path.points.first?.lane ?? 0,
                isHighlighted: true
            )
        }
        let dots = nodes.map { node in
            SourceGit.GraphDot(
                center: CGPoint(
                    x: 10 + Double(node.lane) * 12,
                    y: Double(node.rowIndex) + 0.5
                ),
                lane: node.lane,
                type: node.commit.isMerge ? .merge : .default,
                colorIndex: node.lane,
                isHighlighted: true
            )
        }

        self.model = SourceGit.CommitGraphModel(
            paths: convertedPaths,
            links: [],
            dots: dots,
            laneCount: laneCount,
            commitMetadata: [:]
        )
    }

    var body: some View {
        Canvas { context, _ in
            drawGraph(in: &context)
        }
        .frame(
            width: graphWidth,
            height: CGFloat(model.dots.count) * rowHeight
        )
        .fixedSize()
        .accessibilityHidden(true)
    }

    private var graphWidth: CGFloat {
        CGFloat(model.laneCount) * laneWidth + graphTrailingPadding
    }

    private func drawGraph(in context: inout GraphicsContext) {
        let strokeStyle = StrokeStyle(
            lineWidth: 2.2,
            lineCap: .round,
            lineJoin: .round
        )

        for link in model.links {
            context.stroke(
                Self.linkPath(
                    for: link,
                    rowHeight: rowHeight,
                    laneWidth: laneWidth
                ),
                with: .color(lineColor(
                    colorIndex: link.colorIndex,
                    isHighlighted: link.isHighlighted
                )),
                style: strokeStyle
            )
        }

        for graphPath in model.paths {
            context.stroke(
                Self.path(
                    for: graphPath,
                    rowHeight: rowHeight,
                    laneWidth: laneWidth
                ),
                with: .color(lineColor(
                    colorIndex: graphPath.colorIndex,
                    isHighlighted: graphPath.isHighlighted
                )),
                style: strokeStyle
            )
        }

        for dot in model.dots {
            drawDot(dot, in: &context)
        }
    }

    private func lineColor(colorIndex: Int, isHighlighted: Bool) -> Color {
        isHighlighted
            ? SourceGit.GraphPalette.color(for: colorIndex)
            : Color.gray.opacity(0.4)
    }

    private func drawDot(
        _ dot: SourceGit.GraphDot,
        in context: inout GraphicsContext
    ) {
        let center = Self.position(
            for: dot.center,
            rowHeight: rowHeight,
            laneWidth: laneWidth
        )
        let color = lineColor(
            colorIndex: dot.colorIndex,
            isHighlighted: dot.isHighlighted
        )
        let background = Color(nsColor: .windowBackgroundColor)
        let outerPath = Self.dotPath(
            for: dot,
            rowHeight: rowHeight,
            laneWidth: laneWidth,
            dotSize: dotSize
        )

        switch dot.type {
        case .default:
            context.fill(outerPath, with: .color(color))
            context.stroke(outerPath, with: .color(background), lineWidth: 1.5)

        case .head:
            context.fill(outerPath, with: .color(background))
            context.stroke(outerPath, with: .color(color), lineWidth: 2)

            let innerSize = dotSize - 2
            let innerRect = CGRect(
                x: center.x - innerSize / 2,
                y: center.y - innerSize / 2,
                width: innerSize,
                height: innerSize
            )
            context.fill(Path(ellipseIn: innerRect), with: .color(color))

        case .merge:
            context.fill(outerPath, with: .color(color))

            let plusRadius: CGFloat = 3
            context.stroke(
                Path { path in
                    path.move(to: CGPoint(x: center.x, y: center.y - plusRadius))
                    path.addLine(to: CGPoint(x: center.x, y: center.y + plusRadius))
                },
                with: .color(background),
                lineWidth: 2
            )
            context.stroke(
                Path { path in
                    path.move(to: CGPoint(x: center.x - plusRadius, y: center.y))
                    path.addLine(to: CGPoint(x: center.x + plusRadius, y: center.y))
                },
                with: .color(background),
                lineWidth: 2
            )
        }
    }

    static func path(
        for graphPath: SourceGit.GraphPath,
        rowHeight: CGFloat,
        laneWidth: CGFloat
    ) -> Path {
        var path = Path()
        let points = graphPath.points
        guard points.count > 1 else { return path }

        var last = position(
            for: points[0],
            rowHeight: rowHeight,
            laneWidth: laneWidth
        )
        path.move(to: last)

        for index in 1..<points.count {
            let current = position(
                for: points[index],
                rowHeight: rowHeight,
                laneWidth: laneWidth
            )

            if current.x > last.x {
                path.addQuadCurve(
                    to: current,
                    control: CGPoint(x: current.x, y: last.y)
                )
            } else if current.x < last.x {
                if index < points.count - 1 {
                    let middleY = (last.y + current.y) / 2
                    path.addCurve(
                        to: current,
                        control1: CGPoint(x: last.x, y: middleY + 4),
                        control2: CGPoint(x: current.x, y: middleY - 4)
                    )
                } else {
                    path.addQuadCurve(
                        to: current,
                        control: CGPoint(x: last.x, y: current.y)
                    )
                }
            } else {
                path.addLine(to: current)
            }

            last = current
        }

        return path
    }

    static func linkPath(
        for link: SourceGit.GraphLink,
        rowHeight: CGFloat,
        laneWidth: CGFloat
    ) -> Path {
        var path = Path()
        path.move(to: position(
            for: link.start,
            rowHeight: rowHeight,
            laneWidth: laneWidth
        ))
        path.addQuadCurve(
            to: position(
                for: link.end,
                rowHeight: rowHeight,
                laneWidth: laneWidth
            ),
            control: position(
                for: link.control,
                rowHeight: rowHeight,
                laneWidth: laneWidth
            )
        )
        return path
    }

    static func dotPath(
        for dot: SourceGit.GraphDot,
        rowHeight: CGFloat,
        laneWidth: CGFloat,
        dotSize: CGFloat
    ) -> Path {
        let center = position(
            for: dot.center,
            rowHeight: rowHeight,
            laneWidth: laneWidth
        )
        let size = dot.type == .default ? dotSize : dotSize + 4
        return Path(ellipseIn: CGRect(
            x: center.x - size / 2,
            y: center.y - size / 2,
            width: size,
            height: size
        ))
    }

    private static func position(
        for point: CGPoint,
        rowHeight: CGFloat,
        laneWidth: CGFloat
    ) -> CGPoint {
        CGPoint(
            x: CGFloat((point.x - 10) / 12) * laneWidth + laneWidth / 2,
            y: CGFloat(point.y) * rowHeight
        )
    }
}
