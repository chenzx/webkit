// -*- c-basic-offset: 2 -*-
/*
 *  Copyright (C) 1999-2000 Harri Porten (porten@kde.org)
 *  Copyright (C) 2007 Apple Inc. All Rights Reserved.
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

#include "config.h"
#include "math_object.h"
#include "math_object.lut.h"
#include <wtf/MathExtras.h>

#include "operations.h"
#include <math.h>
#include <time.h>
#include <wtf/Assertions.h>

using namespace KJS;

// ------------------------------ MathObjectImp --------------------------------

const ClassInfo MathObjectImp::info = { "Math", 0, &mathTable, 0 };

/* Source for math_object.lut.h
@begin mathTable 21
  E             MathObjectImp::Euler    DontEnum|DontDelete|ReadOnly
  LN2           MathObjectImp::Ln2      DontEnum|DontDelete|ReadOnly
  LN10          MathObjectImp::Ln10     DontEnum|DontDelete|ReadOnly
  LOG2E         MathObjectImp::Log2E    DontEnum|DontDelete|ReadOnly
  LOG10E        MathObjectImp::Log10E   DontEnum|DontDelete|ReadOnly
  PI            MathObjectImp::Pi       DontEnum|DontDelete|ReadOnly
  SQRT1_2       MathObjectImp::Sqrt1_2  DontEnum|DontDelete|ReadOnly
  SQRT2         MathObjectImp::Sqrt2    DontEnum|DontDelete|ReadOnly
  abs           MathObjectImp::Abs      DontEnum|Function 1
  acos          MathObjectImp::ACos     DontEnum|Function 1
  asin          MathObjectImp::ASin     DontEnum|Function 1
  atan          MathObjectImp::ATan     DontEnum|Function 1
  atan2         MathObjectImp::ATan2    DontEnum|Function 2
  ceil          MathObjectImp::Ceil     DontEnum|Function 1
  cos           MathObjectImp::Cos      DontEnum|Function 1
  exp           MathObjectImp::Exp      DontEnum|Function 1
  floor         MathObjectImp::Floor    DontEnum|Function 1
  log           MathObjectImp::Log      DontEnum|Function 1
  max           MathObjectImp::Max      DontEnum|Function 2
  min           MathObjectImp::Min      DontEnum|Function 2
  pow           MathObjectImp::Pow      DontEnum|Function 2
  random        MathObjectImp::Random   DontEnum|Function 0
  round         MathObjectImp::Round    DontEnum|Function 1
  sin           MathObjectImp::Sin      DontEnum|Function 1
  sqrt          MathObjectImp::Sqrt     DontEnum|Function 1
  tan           MathObjectImp::Tan      DontEnum|Function 1
@end
*/

MathObjectImp::MathObjectImp(ExecState * /*exec*/,
                             ObjectPrototype *objProto)
  : JSObject(objProto)
{
}

// ECMA 15.8

bool MathObjectImp::getOwnPropertySlot(ExecState *exec, const Identifier& propertyName, PropertySlot &slot)
{
  return getStaticPropertySlot<MathFuncImp, MathObjectImp, JSObject>(exec, &mathTable, this, propertyName, slot);
}

JSValue *MathObjectImp::getValueProperty(ExecState *, int token) const
{
  double d = -42; // ;)
  switch (token) {
  case Euler:
    d = exp(1.0);
    break;
  case Ln2:
    d = log(2.0);
    break;
  case Ln10:
    d = log(10.0);
    break;
  case Log2E:
    d = 1.0/log(2.0);
    break;
  case Log10E:
    d = 1.0/log(10.0);
    break;
  case Pi:
    d = piDouble;
    break;
  case Sqrt1_2:
    d = sqrt(0.5);
    break;
  case Sqrt2:
    d = sqrt(2.0);
    break;
  default:
    ASSERT(0);
  }

  return jsNumber(d);
}

// ------------------------------ MathObjectImp --------------------------------

static bool didInitRandom;

MathFuncImp::MathFuncImp(ExecState* exec, int i, int l, const Identifier& name)
  : InternalFunctionImp(static_cast<FunctionPrototype*>(exec->lexicalInterpreter()->builtinFunctionPrototype()), name)
  , id(i)
{
  putDirect(exec->propertyNames().length, l, DontDelete|ReadOnly|DontEnum);
}

JSValue *MathFuncImp::callAsFunction(ExecState *exec, JSObject* /*thisObj*/, const List &args)
{
  double arg = args[0]->toNumber(exec);
  double arg2 = args[1]->toNumber(exec);
  double result;

  switch (id) {
  case MathObjectImp::Abs:
    result = signbit(arg) ? -arg : arg;
    break;
  case MathObjectImp::ACos:
    result = acos(arg);
    break;
  case MathObjectImp::ASin:
    result = asin(arg);
    break;
  case MathObjectImp::ATan:
    result = atan(arg);
    break;
  case MathObjectImp::ATan2:
    result = atan2(arg, arg2);
    break;
  case MathObjectImp::Ceil:
    if (signbit(arg) && arg > -1.0)
      result = -0.0;
    else
      result = ceil(arg);
    break;
  case MathObjectImp::Cos:
    result = cos(arg);
    break;
  case MathObjectImp::Exp:
    result = exp(arg);
    break;
  case MathObjectImp::Floor:
    if (signbit(arg) && arg == 0.0)
      result = -0.0;
    else
      result = floor(arg);
    break;
  case MathObjectImp::Log:
    result = log(arg);
    break;
  case MathObjectImp::Max: {
    unsigned int argsCount = args.size();
    result = -Inf;
    for ( unsigned int k = 0 ; k < argsCount ; ++k ) {
      double val = args[k]->toNumber(exec);
      if ( isNaN( val ) )
      {
        result = NaN;
        break;
      }
      if ( val > result || (val == 0 && result == 0 && !signbit(val)) )
        result = val;
    }
    break;
  }
  case MathObjectImp::Min: {
    unsigned int argsCount = args.size();
    result = +Inf;
    for ( unsigned int k = 0 ; k < argsCount ; ++k ) {
      double val = args[k]->toNumber(exec);
      if ( isNaN( val ) )
      {
        result = NaN;
        break;
      }
      if ( val < result || (val == 0 && result == 0 && signbit(val)) )
        result = val;
    }
    break;
  }
  case MathObjectImp::Pow:
    // ECMA 15.8.2.1.13 (::pow takes care of most of the critera)
    if (isNaN(arg2))
      result = NaN;
    else if (isInf(arg2) && fabs(arg) == 1)
      result = NaN;
    else
      result = ::pow(arg, arg2);
    break;
  case MathObjectImp::Random:
      if (!didInitRandom) {
          wtf_random_init();
          didInitRandom = true;
      }
      result = wtf_random();
      break;
  case MathObjectImp::Round:
    if (signbit(arg) && arg >= -0.5)
        result = -0.0;
    else
        result = floor(arg + 0.5);
    break;
  case MathObjectImp::Sin:
    result = sin(arg);
    break;
  case MathObjectImp::Sqrt:
    result = sqrt(arg);
    break;
  case MathObjectImp::Tan:
    result = tan(arg);
    break;

  default:
    result = 0.0;
    ASSERT(0);
  }

  return jsNumber(result);
}
