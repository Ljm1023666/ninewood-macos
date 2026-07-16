import SwiftUI

/// Workspace：吃满宽的主从栏外壳（列表 | 详情）
struct SplitListDetailShell<ListPane: View, DetailPane: View>: View {
    var minListWidth: CGFloat = 300
    var idealListWidth: CGFloat = 380
    @ViewBuilder var list: () -> ListPane
    @ViewBuilder var detail: () -> DetailPane

    var body: some View {
        HStack(spacing: 0) {
            list()
                .paneColumn(minWidth: minListWidth, idealWidth: idealListWidth)
            Divider()
            detail()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppTheme.workspaceBackground)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.groupedBackground)
    }
}

/// Document：居中限宽内容柱（发布 / 设置 / 认证等）
struct DocumentShell<Content: View>: View {
    var maxWidth: CGFloat = AppTheme.documentMaxWidth
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            content()
                .frame(maxWidth: maxWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, AppTheme.space24)
                .padding(.vertical, AppTheme.space24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.documentBackground)
    }
}
