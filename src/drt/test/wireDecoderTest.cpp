// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2020-2026, The OpenROAD Authors

// R-0915-74(c) — DRT-1010 on wires that are not diagonal.
//
// `io.cpp` walks a net's `dbWire` and turns it into `frPathSeg`s.  Its
// end-of-path look-ahead asked `pathId == POINT` only, so a direction change
// whose next point carried a WIRE EXTENSION (POINT_EXT) was not seen: the path
// was not ended at the turn, and the next pass of the same loop overwrote the
// segment's END with the point AFTER the turn.  The result is a segment whose
// begin and end differ in BOTH axes, which
// `FlexDRWorker::initNetObjs_pathSeg` then reports as
// "Unsupported non-orthogonal wire" (DRT-1010).
//
// MEASURED, sha256 x sky130A, OpenROAD 26Q3-2075-g18e98f9e44: 55 DRT-1010 on a
// design carrying ZERO non-orthogonal segments — 0 of 82,823 net x layer
// routing groups across four DEF checkpoints.  The wire reproduced below is
// net `f_reg[28]` from that run, verbatim:
//
//     NEW met1 ( 508990 218450 ) ( 509910 * )    <- horizontal
//     NEW met1 ( 509910 218450 ) ( * 218790 0 )  <- vertical, WITH an extension
//
// and the error it produced was
//
//     begin=(508.99, 218.45) end=(509.91, 218.79)
//
// i.e. the START of the horizontal segment paired with the END of the vertical
// one.

#include <array>
#include <memory>
#include <string>
#include <vector>

#include "gtest/gtest.h"
#include "io/decodePoint.h"
#include "odb/db.h"
#include "odb/dbTypes.h"
#include "odb/dbWireCodec.h"

namespace drt {
namespace {

struct Segment
{
  int begin_x;
  int begin_y;
  int end_x;
  int end_y;

  bool isOrthogonal() const { return begin_x == end_x || begin_y == end_y; }
};

// The walk under test, reduced to the part the defect lives in: read points,
// end the path when the direction changes, and report the segments.  It is the
// same two-line decision `io.cpp` makes, driven by the same helper.
std::vector<Segment> decodeSegments(odb::dbWire* wire)
{
  std::vector<Segment> segs;
  odb::dbWireDecoder decoder;
  decoder.begin(wire);

  odb::dbWireDecoder::OpCode op = decoder.next();
  bool has_begin = false;
  bool has_end = false;
  bool orthogonal_conn = false;
  int begin_x = -1, begin_y = -1, end_x = -1, end_y = -1;

  while (op != odb::dbWireDecoder::END_DECODE) {
    if (orthogonal_conn) {
      has_begin = true;
      begin_x = end_x;
      begin_y = end_y;
    } else {
      has_begin = false;
      begin_x = begin_y = -1;
    }
    has_end = false;
    orthogonal_conn = false;
    end_x = end_y = -1;

    bool endpath = false;
    do {
      int px = 0, py = 0;
      if (decoderReadPoint(decoder, op, px, py)) {
        if (!has_begin) {
          begin_x = px;
          begin_y = py;
          has_begin = true;
        } else {
          end_x = px;
          end_y = py;
          has_end = true;
        }
      }

      op = decoder.next();

      int nx = 0, ny = 0;
      if (has_end && decoderReadPoint(decoder, op, nx, ny)) {
        const bool curr_vertical = begin_x == end_x;
        const bool next_vertical = end_x == nx;
        orthogonal_conn = curr_vertical != next_vertical;
      }

      if ((int) op <= 3 || op == odb::dbWireDecoder::END_DECODE
          || orthogonal_conn) {
        endpath = true;
      }
    } while (!endpath);

    if (has_end) {
      segs.push_back({begin_x, begin_y, end_x, end_y});
    }
  }
  return segs;
}

class WireDecoderTurnTest : public ::testing::Test
{
 protected:
  void SetUp() override
  {
    db_ = odb::dbDatabase::create();
    tech_ = odb::dbTech::create(db_, "tech");
    layer_ = odb::dbTechLayer::create(
        tech_, "met1", odb::dbTechLayerType::ROUTING);
    lib_ = odb::dbLib::create(db_, "lib", tech_);
    chip_ = odb::dbChip::create(db_, tech_);
    block_ = odb::dbBlock::create(chip_, "top");
  }

  void TearDown() override { odb::dbDatabase::destroy(db_); }

  odb::dbWire* encode(const std::vector<std::array<int, 3>>& pts,
                      const char* net_name)
  {
    odb::dbNet* net = odb::dbNet::create(block_, net_name);
    odb::dbWire* wire = odb::dbWire::create(net);
    odb::dbWireEncoder encoder;
    encoder.begin(wire);
    encoder.newPath(layer_, odb::dbWireType::ROUTED);
    for (const auto& p : pts) {
      if (p[2] < 0) {
        encoder.addPoint(p[0], p[1]);
      } else {
        encoder.addPoint(p[0], p[1], p[2]);
      }
    }
    encoder.end();
    return wire;
  }

  odb::dbDatabase* db_ = nullptr;
  odb::dbTech* tech_ = nullptr;
  odb::dbTechLayer* layer_ = nullptr;
  odb::dbLib* lib_ = nullptr;
  odb::dbChip* chip_ = nullptr;
  odb::dbBlock* block_ = nullptr;
};

// THE DEFECT, with run15's own coordinates.  Horizontal then vertical, and the
// turn point carries an extension.  Before the fix this yielded ONE segment
// (508990, 218450) -> (509910, 218790) — the diagonal DRT-1010 reported.
TEST_F(WireDecoderTurnTest, ATurnIntoAnExtendedPointIsStillATurn)
{
  odb::dbWire* wire = encode({{508990, 218450, -1},
                              {509910, 218450, -1},
                              {509910, 218790, 0}},
                             "f_reg_28");
  const std::vector<Segment> segs = decodeSegments(wire);

  ASSERT_EQ(segs.size(), 2u);
  for (const Segment& s : segs) {
    EXPECT_TRUE(s.isOrthogonal())
        << "(" << s.begin_x << ", " << s.begin_y << ") -> (" << s.end_x << ", "
        << s.end_y << ")";
  }
  EXPECT_EQ(segs[0].begin_x, 508990);
  EXPECT_EQ(segs[0].end_x, 509910);
  EXPECT_EQ(segs[0].begin_y, 218450);
  EXPECT_EQ(segs[0].end_y, 218450);
  EXPECT_EQ(segs[1].begin_y, 218450);
  EXPECT_EQ(segs[1].end_y, 218790);
  EXPECT_EQ(segs[1].begin_x, 509910);
  EXPECT_EQ(segs[1].end_x, 509910);
}

// The same turn WITHOUT an extension already worked, and must keep working.
TEST_F(WireDecoderTurnTest, ATurnIntoAPlainPointIsUnchanged)
{
  odb::dbWire* wire = encode({{508990, 218450, -1},
                              {509910, 218450, -1},
                              {509910, 218790, -1}},
                             "plain_turn");
  const std::vector<Segment> segs = decodeSegments(wire);

  ASSERT_EQ(segs.size(), 2u);
  for (const Segment& s : segs) {
    EXPECT_TRUE(s.isOrthogonal());
  }
}

// NEGATIVE CONTROL 1 — no turn.  Three collinear points must stay ONE segment;
// a fix that ended the path at every point would pass the test above and break
// this.
TEST_F(WireDecoderTurnTest, AStraightRunIsNotSplit)
{
  odb::dbWire* wire = encode({{508990, 218450, -1},
                              {509910, 218450, -1},
                              {510830, 218450, 0}},
                             "straight");
  const std::vector<Segment> segs = decodeSegments(wire);

  ASSERT_EQ(segs.size(), 1u);
  EXPECT_EQ(segs[0].begin_x, 508990);
  EXPECT_EQ(segs[0].end_x, 510830);
  EXPECT_TRUE(segs[0].isOrthogonal());
}

// NEGATIVE CONTROL 2 — a wire that really IS diagonal is still reported as
// such.  DRT-1010 must keep firing on geometry that deserves it.
TEST_F(WireDecoderTurnTest, AGenuinelyDiagonalWireIsStillNonOrthogonal)
{
  odb::dbWire* wire
      = encode({{508990, 218450, -1}, {509910, 218790, -1}}, "diagonal");
  const std::vector<Segment> segs = decodeSegments(wire);

  ASSERT_EQ(segs.size(), 1u);
  EXPECT_FALSE(segs[0].isOrthogonal());
}

// NEGATIVE CONTROL 3 — the same, with the diagonal's end carrying an
// extension: the extension must not launder a diagonal into an orthogonal
// pair.
TEST_F(WireDecoderTurnTest, AnExtendedDiagonalIsStillNonOrthogonal)
{
  odb::dbWire* wire
      = encode({{508990, 218450, -1}, {509910, 218790, 0}}, "diagonal_ext");
  const std::vector<Segment> segs = decodeSegments(wire);

  ASSERT_EQ(segs.size(), 1u);
  EXPECT_FALSE(segs[0].isOrthogonal());
}

// The helper itself: a non-point opcode is refused rather than mis-read.
TEST_F(WireDecoderTurnTest, ANonPointOpcodeIsRefused)
{
  odb::dbWire* wire
      = encode({{508990, 218450, -1}, {509910, 218450, -1}}, "opcode");
  odb::dbWireDecoder decoder;
  decoder.begin(wire);
  const odb::dbWireDecoder::OpCode op = decoder.next();  // PATH
  ASSERT_EQ(op, odb::dbWireDecoder::PATH);
  int x = -1, y = -1;
  EXPECT_FALSE(decoderReadPoint(decoder, op, x, y));
  EXPECT_EQ(x, -1);
  EXPECT_EQ(y, -1);
}

}  // namespace
}  // namespace drt
