import SwiftUI
import MarkdownUI
import Splash

struct SplashCodeSyntaxHighlighter: CodeSyntaxHighlighter {
    private let syntaxHighlighter: SyntaxHighlighter<AttributedStringOutputFormat>
    
    init(theme: Splash.Theme) {
        self.syntaxHighlighter = SyntaxHighlighter(format: AttributedStringOutputFormat(theme: theme))
    }
    
    func highlightCode(_ content: String, language: String?) -> Text {
        guard language?.isEmpty == false else {
            return Text(content)
        }
        
        let nsAttributedString = self.syntaxHighlighter.highlight(content)
        let attributedString = try? AttributedString(nsAttributedString, including: \.uiKit)
        
        if let attributedString = attributedString {
            return Text(attributedString)
        } else {
            return Text(content)
        }
    }
}

extension CodeSyntaxHighlighter where Self == SplashCodeSyntaxHighlighter {
    static func splash(theme: Splash.Theme = .sunset(withFont: .init(size: 14))) -> Self {
        SplashCodeSyntaxHighlighter(theme: theme)
    }
}
