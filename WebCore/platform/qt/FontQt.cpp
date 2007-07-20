/*
    Copyright (C) 2007 Trolltech ASA

    This library is free software; you can redistribute it and/or
    modify it under the terms of the GNU Library General Public
    License as published by the Free Software Foundation; either
    version 2 of the License, or (at your option) any later version.

    This library is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
    Library General Public License for more details.

    You should have received a copy of the GNU Library General Public License
    along with this library; see the file COPYING.LIB.  If not, write to
    the Free Software Foundation, Inc., 59 Temple Place - Suite 330,
    Boston, MA 02111-1307, USA.

    This class provides all functionality needed for loading images, style sheets and html
    pages from the web. It has a memory cache for these objects.
*/
#include "config.h"
#include "Font.h"
#include "FontDescription.h"
#include "TextStyle.h"

#include "GraphicsContext.h"
#include <QTextLayout>
#include <QPainter>
#include <QFontMetrics>
#include <QFontInfo>
#include <qalgorithms.h>
#include <qdebug.h>

#include <limits.h>
namespace WebCore {

struct TextRunComponent {
    TextRunComponent() : font(0) {}
    TextRunComponent(const UChar *start, int length, bool rtl, const QFont *font, int offset, bool sc = false);
    QString string;
    const QFont *font;
    int width;
    int offset;
};

TextRunComponent::TextRunComponent(const UChar *start, int length, bool rtl, const QFont *f, int o, bool sc)
    : string(reinterpret_cast<const QChar*>(start), length)
    , font(f)
    , offset(o)
{
    if (sc)
        string = string.toUpper();
    string.prepend(rtl ? QChar(0x202e) : QChar(0x202d));
    width = QFontMetrics(*font).width(string);
}


Font::Font()
    : m_letterSpacing(0)
    , m_wordSpacing(0)
    , m_font()
    , m_scFont()
{
    QFontMetrics metrics(m_font);
    m_spaceWidth = metrics.width(QLatin1Char(' '));
    qreal pointsize = m_font.pointSizeF();
    if (pointsize > 0)
        m_scFont.setPointSizeF(pointsize*0.7);
    else
        m_scFont.setPixelSize(qRound(m_font.pixelSize()*.7));
}

Font::Font(const FontDescription& description, short letterSpacing, short wordSpacing)
    : m_fontDescription(description)
    , m_letterSpacing(letterSpacing)
    , m_wordSpacing(wordSpacing)
{
    const FontFamily* family = &description.family();
    QString familyName;
    while (family) {
        familyName += family->family();
        family = family->next();
        if (family)
            familyName += QLatin1Char(',');
    }

    m_font.setFamily(familyName);
    m_font.setPixelSize(qRound(description.computedSize()));
    m_font.setItalic(description.italic());
    if (description.bold()) {
        // Qt's Bold is 75, Webkit is 63.
        m_font.setWeight(QFont::Bold);
    } else {
        m_font.setWeight(description.weight());
    }
    QFontMetrics metrics = QFontMetrics(m_font);
    m_spaceWidth = metrics.width(QLatin1Char(' '));
    m_scFont = m_font;
    m_scFont.setPixelSize(qRound(description.computedSize()*.7));
}

Font::~Font()
{
}
    
Font::Font(const Font& other)
    : m_fontDescription(other.m_fontDescription)
    , m_letterSpacing(other.m_letterSpacing)
    , m_wordSpacing(other.m_wordSpacing)
    , m_font(other.m_font)
    , m_scFont(other.m_scFont)
    , m_spaceWidth(other.m_spaceWidth)
{
}

Font& Font::operator=(const Font& other)
{
    m_fontDescription = other.m_fontDescription;
    m_letterSpacing = other.m_letterSpacing;
    m_wordSpacing = other.m_wordSpacing;
    m_font = other.m_font;
    m_scFont = other.m_scFont;
    m_spaceWidth = other.m_spaceWidth;
    return *this;
}

void Font::update() const
{
    // don't think we need this
}

static int generateComponents(Vector<TextRunComponent, 1024>* components, const Font &font, const TextRun &run, const TextStyle &style)
{
//     qDebug() << "generateComponents" << QString((const QChar *)run.characters(), run.length());
    int letterSpacing = font.letterSpacing();
    int wordSpacing = font.wordSpacing();
    bool smallCaps = font.fontDescription().smallCaps();
    int padding = style.padding();
    int numSpaces = 0;
    if (padding) {
        for (int i = 0; i < run.length(); i++)
            if (Font::treatAsSpace(run[i]))
                ++numSpaces;      
    }

    int offset = 0;
    const QFont *f = &font.font();
    if (letterSpacing || smallCaps) {
        // need to draw every letter on it's own
        int start = 0;
        if (Font::treatAsSpace(run[0])) {
            int add = 0;
            if (numSpaces) {
                add = padding/numSpaces;
                padding -= add;
                --numSpaces;
            }
            offset += add + letterSpacing + font.spaceWidth();
            start = 1;
//         qDebug() << "space at 0" << offset;
        } else if (smallCaps) {
            f = (QChar::category(run[0]) == QChar::Letter_Lowercase ? &font.scFont() : &font.font());
        }
        for (int i = 1; i < run.length(); ++i) {
            uint ch = run[i];
            if (QChar(ch).isHighSurrogate() && QChar(run[i-1]).isLowSurrogate())
                ch = QChar::surrogateToUcs4(ch, run[i-1]);
            if (QChar(ch).isLowSurrogate() || QChar::category(ch) == QChar::Mark_NonSpacing)
                continue;
            if (Font::treatAsSpace(run[i])) {
                int add = 0;
//                 qDebug() << "    treatAsSpace:" << i << start;
                if (i - start > 0) {
                    components->append(TextRunComponent(run.characters() + start, i - start,
                                                        style.rtl(), 
                                                        f, offset, f == &font.scFont()));
                    offset += components->last().width + letterSpacing;
//                     qDebug() << "   appending(1) " << components->last().string << components->last().width;
                }
                if (numSpaces) {
                    add = padding/numSpaces;
                    padding -= add;
                    --numSpaces;
                }
                offset += wordSpacing + add + font.spaceWidth() + letterSpacing;
                start = i + 1;
                continue;
            } else if (!letterSpacing) {
//                 qDebug() << i << char(run[i]) << (QChar::category(ch) == QChar::Letter_Lowercase) <<
//                     QFontInfo(*f).pointSizeF();
                if (QChar::category(ch) == QChar::Letter_Lowercase) {
                    if (f == &font.scFont())
                        continue;
                } else {
                    if (f == &font.font())
                        continue;
                }
            }
            if (i - start > 0) {
                components->append(TextRunComponent(run.characters() + start, i - start,
                                                    style.rtl(), 
                                                    f, offset, f == &font.scFont()));
                offset += components->last().width + letterSpacing;
//                 qDebug() << "   appending(2) " << components->last().string << components->last().width;
            }
            if (smallCaps)
                f = (QChar::category(ch) == QChar::Letter_Lowercase ? &font.scFont() : &font.font());
            start = i;
        }
        if (run.length() - start > 0) {
            components->append(TextRunComponent(run.characters() + start, run.length() - start,
                                                style.rtl(), 
                                                f, offset, f == &font.scFont()));
            offset += components->last().width;
//             qDebug() << "   appending(3) " << components->last().string << components->last().width;
        }
        offset += letterSpacing;
    } else {
        int start = 0;
        for (int i = 0; i < run.length(); ++i) {
            if (Font::treatAsSpace(run[i])) {
                if (i - start > 0) {
                    components->append(TextRunComponent(run.characters() + start, i - start,
                                                        style.rtl(), 
                                                        f, offset));
                    offset += components->last().width;
                }
                int add = 0;
                if (numSpaces) {
                    add = padding/numSpaces;
                    padding -= add;
                    --numSpaces;
                }
                offset += add + font.spaceWidth();
                if (i)
                    offset += wordSpacing;
                start = i + 1;
            }
        }
        if (run.length() - start > 0) {
            components->append(TextRunComponent(run.characters() + start, run.length() - start,
                                                style.rtl(), 
                                                f, offset));
            offset += components->last().width;
        }
    }
    return offset;
}

void Font::drawText(GraphicsContext* ctx, const TextRun& run, const TextStyle& style, const FloatPoint& point, int from, int to) const
{
    if (to < 0)
        to = run.length();
    QPainter *p = ctx->platformContext();
    Color color = ctx->fillColor();
    p->setPen(QColor(color));

    Vector<TextRunComponent, 1024> components;
    int w = generateComponents(&components, *this, run, style);

    if (style.rtl()) {
        for (int i = 0; i < components.size(); ++i) {
            p->setFont(*components.at(i).font);
            QPointF pt(point.x() + w - components.at(i).offset - components.at(i).width, point.y());
            p->drawText(pt, components.at(i).string);
        }
    } else {
        for (int i = 0; i < components.size(); ++i) {
            p->setFont(*components.at(i).font);
            QPointF pt(point.x() + components.at(i).offset, point.y());
            p->drawText(pt, components.at(i).string);
        }
    }
}

int Font::width(const TextRun& run, const TextStyle& style) const
{
    Vector<TextRunComponent, 1024> components;
    int w = generateComponents(&components, *this, run, style);

//     qDebug() << "     width=" << w;
    return w;
}

int Font::width(const TextRun& run) const
{
    return width(run, TextStyle());
}

float Font::floatWidth(const TextRun& run, const TextStyle& style) const
{
    return width(run, style);
}

float Font::floatWidth(const TextRun& run) const
{
    return width(run);
}

int Font::offsetForPosition(const TextRun& run, const TextStyle& style, int position, bool includePartialGlyphs) const
{
    Vector<TextRunComponent, 1024> components;
    int w = generateComponents(&components, *this, run, style);

    int offset = 0;
    if (style.rtl()) {
        for (int i = 0; i < components.size(); ++i) {
            int xe = w - components.at(i).offset;
            int xs = xe - components.at(i).width;
            if (position >= xs && position <= xe) {
                QTextLayout layout(components.at(i).string, m_font);
                layout.beginLayout();
                QTextLine l = layout.createLine();
                if (!l.isValid())
                    return 0;
                
                l.setLineWidth(INT_MAX/256);
                layout.endLayout();
                
                return offset + l.xToCursor(position - xs) - 1;
            } else {
                offset += components.at(i).string.length() - 1;
            }
        }
    } else {
        for (int i = 0; i < components.size(); ++i) {
            int xs = components.at(i).offset;
            int xe = xs + components.at(i).width;
            if (position >= xs && position <= xe) {
                QTextLayout layout(components.at(i).string, m_font);
                layout.beginLayout();
                QTextLine l = layout.createLine();
                if (!l.isValid())
                    return 0;
                
                l.setLineWidth(INT_MAX/256);
                layout.endLayout();
                
                return offset + l.xToCursor(position - xs) - 1;
            } else {
                offset += components.at(i).string.length() - 1;
            }
        }
    }
    return 0;
}

static float cursorToX(const Vector<TextRunComponent, 1024>& components, int width,
                     const TextStyle& style,
                     const QFont& font, int cursor)
{
    int start = 0;
    for (int i = 0; i < components.size(); ++i) {
        if (start + components.at(i).string.length() - 1 < cursor) {
            start += components.at(i).string.length() - 1;
            continue;
        }
        int xs = components.at(i).offset;
        if (style.rtl())
            xs = width - xs - components.at(i).width;
        QTextLayout layout(components.at(i).string, font);
        layout.beginLayout();
        QTextLine l = layout.createLine();
        if (!l.isValid())
            return 0;
        
        l.setLineWidth(INT_MAX/256);
        layout.endLayout();
        
        return xs + l.cursorToX(cursor + 1);
    }
    return width;
}

FloatRect Font::selectionRectForText(const TextRun& run, const TextStyle& style, const IntPoint& pt,
                                     int h, int from, int to) const
{
    Vector<TextRunComponent, 1024> components;
    int w = generateComponents(&components, *this, run, style);

    float x1 = cursorToX(components, w, style, m_font, from);
    float x2 = cursorToX(components, w, style, m_font, to);
    if (x2 < x1)
        qSwap(x1, x2);

//     qDebug() << ">>>>>>>>>>> selectionRectForText: string=" << QString((QChar *)run.characters(), run.length())
//              << "from/to=" << from << to
//              << "x1/x2=" << x1 << x2;
    return FloatRect(pt.x() + x1, pt.y(), x2 - x1, h);
}

bool Font::isFixedPitch() const
{
    return QFontInfo(m_font).fixedPitch();
}

// Metrics that we query the FontFallbackList for.
int Font::ascent() const
{
    return QFontMetrics(m_font).ascent();
}

int Font::descent() const
{
    return QFontMetrics(m_font).descent();
}

int Font::lineSpacing() const
{
    return QFontMetrics(m_font).lineSpacing();
}

float Font::xHeight() const
{
    return QFontMetrics(m_font).xHeight();
}

int Font::spaceWidth() const
{
    return m_spaceWidth;
}

}
