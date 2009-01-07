/*
 *  Copyright (C) 1999-2000 Harri Porten (porten@kde.org)
 *  Copyright (C) 2008 Apple Inc. All rights reserved.
 *
 *  This library is free software; you can redistribute it and/or
 *  modify it under the terms of the GNU Lesser General Public
 *  License as published by the Free Software Foundation; either
 *  version 2 of the License, or (at your option) any later version.
 *
 *  This library is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 *  Lesser General Public License for more details.
 *
 *  You should have received a copy of the GNU Lesser General Public
 *  License along with this library; if not, write to the Free Software
 *  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
 *
 */

#ifndef NumberConstructor_h
#define NumberConstructor_h

#include "InternalFunction.h"

namespace JSC {

    class NumberPrototype;

    class NumberConstructor : public InternalFunction {
    public:
        NumberConstructor(ExecState*, PassRefPtr<Structure>, NumberPrototype*);

        virtual bool getOwnPropertySlot(ExecState*, const Identifier&, PropertySlot&);
        JSValuePtr getValueProperty(ExecState*, int token) const;

        static const ClassInfo info;

        static PassRefPtr<Structure> createStructure(JSValuePtr proto) 
        { 
            return Structure::create(proto, TypeInfo(ObjectType, ImplementsHasInstance)); 
        }

        enum { NaNValue, NegInfinity, PosInfinity, MaxValue, MinValue };

    private:
        virtual ConstructType getConstructData(ConstructData&);
        virtual CallType getCallData(CallData&);

        virtual const ClassInfo* classInfo() const { return &info; }
    };

} // namespace JSC

#endif // NumberConstructor_h
