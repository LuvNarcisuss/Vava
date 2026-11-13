"""Render the two editable English agreement drafts to searchable PDFs."""

from pathlib import Path
from xml.sax.saxutils import escape

from reportlab.lib import colors
from reportlab.lib.styles import ParagraphStyle
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer

root = Path(__file__).resolve().parents[1]
fonts = root / "Assets/Fonts"
output = root / "Assets/Agreements"
pdfmetrics.registerFont(TTFont("Kalam", str(fonts / "Kalam-Bold.ttf")))
pdfmetrics.registerFont(TTFont("ComicNeue", str(fonts / "ComicNeue-Regular.ttf")))
ink = colors.HexColor("#14312A")
styles = {
    "title": ParagraphStyle("Title", fontName="Kalam", fontSize=23, leading=29, textColor=ink, spaceAfter=9),
    "section": ParagraphStyle("Section", fontName="Kalam", fontSize=12.5, leading=15, textColor=ink, spaceBefore=11, spaceAfter=4),
    "text": ParagraphStyle("Body", fontName="ComicNeue", fontSize=11.5, leading=15, textColor=ink, spaceAfter=3),
}
for name in ("terms", "privacy"):
    source = (root / "Assets/AgreementSources" / (name + ".md")).read_text().splitlines()
    story = []
    for line in source:
        if line.startswith("# "):
            story.append(Paragraph(escape(line[2:]), styles["title"]))
        elif line.startswith("## "):
            story.append(Paragraph(escape(line[3:]), styles["section"]))
        elif line:
            story.append(Paragraph(escape(line), styles["text"]))
        else:
            story.append(Spacer(1, 2))
    pdf = SimpleDocTemplate(str(output / (name + ".pdf")), title=source[0][2:], pagesize=(420, 690),
                            topMargin=27, bottomMargin=27, leftMargin=30, rightMargin=30)
    pdf.build(story)
