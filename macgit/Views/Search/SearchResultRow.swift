import SwiftUI

struct SearchResultRow: View {
    let result: SearchResult
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: result.type.icon)
                .font(.system(size: 16))
                .foregroundStyle(isSelected ? .white : .secondary)
                .frame(width: 24, alignment: .center)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(result.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                
                Text(result.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            if let badge = result.badge {
                Text(badge)
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(isSelected ? Color.white.opacity(0.2) : Color.secondary.opacity(0.15))
                    .foregroundStyle(isSelected ? .white : .secondary)
                    .cornerRadius(4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor : Color.clear)
        .foregroundStyle(isSelected ? .white : .primary)
        .cornerRadius(6)
        .contentShape(Rectangle())
    }
}
