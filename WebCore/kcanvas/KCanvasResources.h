/*
    Copyright (C) 2004, 2005 Nikolas Zimmermann <wildfox@kde.org>
                  2004, 2005 Rob Buis <buis@kde.org>

    This file is part of the KDE project

    This library is free software; you can redistribute it and/or
    modify it under the terms of the GNU Library General Public
    License as published by the Free Software Foundation; either
    version 2 of the License, or (at your option) any later version.

    This library is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
    Library General Public License for more details.

    You should have received a copy of the GNU Library General Public License
    aint with this library; see the file COPYING.LIB.  If not, write to
    the Free Software Foundation, Inc., 59 Temple Place - Suite 330,
    Boston, MA 02111-1307, USA.
*/

#ifndef KCanvasResources_H
#define KCanvasResources_H

#include <qstring.h>
#include <q3valuelist.h>

#include <kcanvas/KCanvasItem.h>
#include <kcanvas/KCanvasPath.h>
#include <kcanvas/KCanvasResourceListener.h>

class QTextStream;

// Enumerations
typedef enum
{
    // Painting mode
    RS_CLIPPER = 0,
    RS_MARKER = 1,
    RS_IMAGE = 2,
    RS_FILTER = 3
} KCResourceType;

class KCanvasMatrix;

class KCanvasResource
{
public:
    KCanvasResource();
    virtual ~KCanvasResource();

    virtual void invalidate();
    void addClient(KCanvasItem *item);

    const KCanvasItemList &clients() const;
    
    QString idInRegistry() const;
    void setIdInRegistry(const QString& newId);
    
    virtual QTextStream& externalRepresentation(QTextStream &) const; 
private:
    KCanvasItemList m_clients;
    QString registryId;
};

class KCanvasClipper : public KCanvasResource
{
public:
    KCanvasClipper();
    virtual ~KCanvasClipper();

    // Differentiate between viewport clipping and normal clipping data...
    bool viewportClipper() const;
    void setViewportClipper(bool viewport);

    void resetClipData();
    void addClipData(const KCPathDataList &path, KCWindRule rule, bool bbox);

    KCClipDataList clipData() const;

    QTextStream& externalRepresentation(QTextStream &) const; 
protected:
    bool m_viewportMode : 1;
    KCClipDataList m_clipData;
};

class KCanvasMarker : public KCanvasResource
{
public:
    KCanvasMarker(KCanvasItem *marker = 0);
    virtual ~KCanvasMarker();

    void setMarker(KCanvasItem *marker);

    void setRefX(double refX);
    double refX() const;

    void setRefY(double refY);
    double refY() const;

    void setAutoAngle();
    void setAngle(float angle);
    float angle() const;

    // Draw onto the canvas
    void draw(double x, double y, double angle = 0.0);

    QTextStream& externalRepresentation(QTextStream &) const; 
private:
    double m_refX, m_refY;
    float m_angle;
    KCanvasItem *m_marker;
};

QTextStream &operator<<(QTextStream &ts, const KCanvasResource &r);

#endif

// vim:ts=4:noet
