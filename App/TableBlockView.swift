import NoteCore
import SwiftUI

/// Editable table. Scrolls sideways when it is wider than the screen.
/// The first row is styled as a header.
struct TableBlockView: View {
    @Binding var table: TableContent
    let onDelete: () -> Void

    private let cellWidth: CGFloat = 124

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                    ForEach(table.rows.indices, id: \.self) { row in
                        GridRow {
                            ForEach(table.rows[row].indices, id: \.self) { column in
                                cell(row: row, column: column)
                            }
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                        .stroke(Color.primary.opacity(0.18), lineWidth: 1)
                )
                .padding(1)
            }

            HStack(spacing: 18) {
                Button("Row", systemImage: "plus") { table.addRow() }
                Button("Column", systemImage: "plus") { table.addColumn() }
                Spacer()
                Menu {
                    Button("Delete Last Row", systemImage: "minus") { table.removeRow(at: table.rowCount - 1) }
                        .disabled(table.rowCount <= 1)
                    Button("Delete Last Column", systemImage: "minus") { table.removeColumn(at: table.columnCount - 1) }
                        .disabled(table.columnCount <= 1)
                    Button("Delete Table", systemImage: "trash", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis").frame(width: 30, height: 30)
                }
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(Theme.accent)
            .labelStyle(.titleAndIcon)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private func cell(row: Int, column: Int) -> some View {
        TextField("", text: binding(row: row, column: column), axis: .vertical)
            .font(.system(.callout, design: .serif, weight: row == 0 ? .bold : .regular))
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(width: cellWidth, alignment: .topLeading)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .background(row == 0 ? Theme.card : Color.clear)
            .overlay(Rectangle().stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
    }

    private func binding(row: Int, column: Int) -> Binding<String> {
        Binding(
            get: {
                guard table.rows.indices.contains(row), table.rows[row].indices.contains(column) else { return "" }
                return table.rows[row][column]
            },
            set: { value in
                guard table.rows.indices.contains(row), table.rows[row].indices.contains(column) else { return }
                table.rows[row][column] = value
            }
        )
    }
}
