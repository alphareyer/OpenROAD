// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2020-2026, The OpenROAD Authors

#pragma once

#include "odb/db.h"

namespace drt {

// R-0915-74(c) — READ THE DECODER'S CURRENT POINT, WHETHER OR NOT IT CARRIES
// AN EXTENSION.
//
// `dbWireDecoder` reports a routing point as POINT, or as POINT_EXT when the
// point carries a wire-extension value.  The two are the same geometric fact
// and they are read through DIFFERENT overloads: `getPoint(x, y)` asserts
// `opcode_ == POINT` and `getPoint(x, y, ext)` asserts `opcode_ == POINT_EXT`.
// A caller that tests for only one of them silently skips every point of the
// other kind.
//
// MEASURED, sha256 x sky130A, OpenROAD 26Q3-2075-g18e98f9e44, a 569 um sky130hd
// design.  `FlexDRWorker::initNetObjs_pathSeg` raised DRT-1010 "Unsupported
// non-orthogonal wire" 55 times on a design whose DEF contains ZERO
// non-orthogonal segments — 0 of 82,823 net x layer routing groups across four
// checkpoints.  One example, coordinate for coordinate:
//
//     DRT-1010: begin=(508.99, 218.45) end=(509.91, 218.79) met1 net f_reg[28]
//     DEF:  NEW met1 ( 508990 218450 ) ( 509910 * )    <- horizontal
//           NEW met1 ( 509910 218450 ) ( * 218790 0 )  <- vertical, WITH an ext
//
// `begin` is the start of the horizontal segment and `end` is the end of the
// vertical one: the reader composed a diagonal from one endpoint of each.  Over
// all 55 messages every |dx| was a multiple of 0.46 um and every |dy| a
// multiple of 0.17 um — both endpoints exactly on the routing grid in both
// axes, which is what two real points of two different segments look like.
//
// The cause is in `io.cpp`'s end-of-path look-ahead, which asked
// `pathId == POINT` only.  On POINT_EXT it left `orthogonal_conn` false, the
// path was not ended at the direction change, and the next pass of the same
// iteration overwrote the segment's END with the point after the turn.
//
// Returns false when the opcode is not a point at all, so a caller can keep
// using it as the test it already had.
inline bool decoderReadPoint(const odb::dbWireDecoder& decoder,
                             odb::dbWireDecoder::OpCode opcode,
                             int& x,
                             int& y)
{
  switch (opcode) {
    case odb::dbWireDecoder::POINT:
      decoder.getPoint(x, y);
      return true;
    case odb::dbWireDecoder::POINT_EXT: {
      int ext = 0;
      decoder.getPoint(x, y, ext);
      return true;
    }
    default:
      return false;
  }
}

}  // namespace drt
