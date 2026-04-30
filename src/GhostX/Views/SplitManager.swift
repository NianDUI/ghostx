import SwiftUI

/// Manages terminal split panes — vertical/horizontal/matrix layout
final class SplitManager: ObservableObject {
    enum SplitDirection { case horizontal, vertical }

    class SplitNode: Identifiable {
        let id = UUID()
        var direction: SplitDirection?
        var children: [SplitNode] = []
        var tabID: UUID?

        var isLeaf: Bool { tabID != nil }
        var isEmpty: Bool { tabID == nil && children.isEmpty }

        init(tabID: UUID? = nil, direction: SplitDirection? = nil, children: [SplitNode] = []) {
            self.tabID = tabID
            self.direction = direction
            self.children = children
        }

        static func leaf(tabID: UUID) -> SplitNode { SplitNode(tabID: tabID) }
        static func container(direction: SplitDirection, children: [SplitNode]) -> SplitNode {
            SplitNode(direction: direction, children: children)
        }
    }

    @Published var root: SplitNode = .leaf(tabID: UUID())  // placeholder, replaced on first tab
    @Published var focusedNodeID: UUID?

    func splitCurrent(direction: SplitDirection, newTabID: UUID) {
        guard let focusedID = focusedNodeID else {
            root = .leaf(tabID: newTabID)
            focusedNodeID = root.id
            return
        }

        // Find the leaf and split it
        if !findAndReplace(nodeID: focusedID, in: &root, direction: direction, newTabID: newTabID) {
            // Not found as child — wrap root
            root = .container(direction: direction, children: [root, .leaf(tabID: newTabID)])
            focusedNodeID = root.children.last?.id
        }
        objectWillChange.send()
    }

    @discardableResult
    private func findAndReplace(nodeID: UUID, in node: inout SplitNode, direction: SplitDirection, newTabID: UUID) -> Bool {
        // Check children
        for i in node.children.indices {
            if node.children[i].id == nodeID {
                let newNode = SplitNode.container(
                    direction: direction,
                    children: [node.children[i], .leaf(tabID: newTabID)]
                )
                node.children[i] = newNode
                focusedNodeID = newNode.children.last?.id
                return true
            }
            var child = node.children[i]
            if findAndReplace(nodeID: nodeID, in: &child, direction: direction, newTabID: newTabID) {
                node.children[i] = child
                return true
            }
        }
        return false
    }

    func closeTab(tabID: UUID) {
        closeInTree(tabID: tabID, in: &root)
        objectWillChange.send()
    }

    @discardableResult
    private func closeInTree(tabID: UUID, in node: inout SplitNode) -> Bool {
        for i in node.children.indices {
            var child = node.children[i]

            // If leaf matches, remove it
            if child.tabID == tabID {
                node.children.remove(at: i)
                // Collapse single child
                if node.children.count == 1, let only = node.children.first {
                    node.direction = only.direction
                    node.children = only.children
                    node.tabID = only.tabID
                }
                return true
            }

            // Recurse
            if closeInTree(tabID: tabID, in: &child) {
                node.children[i] = child
                return true
            }
        }
        return false
    }

    func focusLeaf(id: UUID) {
        focusedNodeID = id
        objectWillChange.send()
    }

    func nodeID(for tabID: UUID) -> UUID? {
        findNode(tabID: tabID, in: root)?.id
    }

    private func findNode(tabID: UUID, in node: SplitNode) -> SplitNode? {
        if node.tabID == tabID { return node }
        for child in node.children {
            if let found = findNode(tabID: tabID, in: child) { return found }
        }
        return nil
    }
}

/// Renders the split tree recursively
struct SplitTreeView: View {
    @ObservedObject var splitManager: SplitManager
    @ObservedObject var tabManager: TabManager
    let node: SplitManager.SplitNode

    var body: some View {
        if let direction = node.direction, !node.children.isEmpty {
            if direction == .horizontal {
                HSplitView {
                    ForEach(node.children) { child in
                        SplitTreeView(splitManager: splitManager, tabManager: tabManager, node: child)
                    }
                }
            } else {
                VSplitView {
                    ForEach(node.children) { child in
                        SplitTreeView(splitManager: splitManager, tabManager: tabManager, node: child)
                    }
                }
            }
        } else if let tabID = node.tabID,
                  let tab = tabManager.tabs.first(where: { $0.id == tabID }) {
            TerminalView(client: tab.client, config: tab.config)
                .overlay(alignment: .topTrailing) {
                    HStack(spacing: 2) {
                        Button(action: { splitManager.splitCurrent(direction: .horizontal, newTabID: tabID) }) {
                            Image(systemName: "rectangle.righthalf.inset.filled").font(.system(size: 8))
                        }
                        .buttonStyle(.borderless).help(L10n.splitH)
                        Button(action: { splitManager.splitCurrent(direction: .vertical, newTabID: tabID) }) {
                            Image(systemName: "rectangle.bottomhalf.inset.filled").font(.system(size: 8))
                        }
                        .buttonStyle(.borderless).help(L10n.splitV)
                    }
                    .padding(2).opacity(0.5)
                }
                .onAppear { splitManager.focusLeaf(id: node.id) }
                .onTapGesture { splitManager.focusLeaf(id: node.id) }
        } else {
            VStack {
                Image(systemName: "terminal").font(.system(size: 48)).foregroundColor(.secondary)
                Text(L10n.noTerminal).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.black)
        }
    }
}
