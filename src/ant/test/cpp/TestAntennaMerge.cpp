// SPDX-License-Identifier: BSD-3-Clause
// Copyright (c) 2026, The OpenROAD Authors

#include <string>
#include <vector>

#include "ant/AntennaChecker.hh"
#include "gtest/gtest.h"
#include "odb/db.h"
#include "odb/dbTypes.h"
#include "tst/db_fixture.h"
#include "tst/physical_builder.h"

namespace ant {
namespace {

class AntennaMergeTest : public tst::DbFixture
{
 protected:
  void SetUp() override
  {
    auto* tech = tst::makeTech(getDb());
    layer_ = tst::addRoutingLayer(tech, "M1", {.width = 1000});
    tst::applyAntennaRule(layer_,
                          {.par = 100.0, .diff_par = tst::constantPwl(100.0)});
    auto* lib = tst::makeLib(getDb(), tech);
    block_ = tst::makeBlock(getDb(), tech);
    gate_ = tst::makeMaster(lib,
                            "gate",
                            1000,
                            1000,
                            {{.name = "A",
                              .layer = layer_,
                              .rect = {-500, -500, 500, 500},
                              .gate_area = 0.01}});
    diode_ = tst::makeMaster(lib,
                             "diode",
                             1000,
                             1000,
                             {{.name = "D",
                               .layer = layer_,
                               .rect = {-500, -500, 500, 500},
                               .diff_area = 0.1}},
                             odb::dbMasterType::CORE_ANTENNACELL);
  }

  odb::dbNet* routedNet(const char* name)
  {
    auto* net = odb::dbNet::create(block_, name);
    auto* inst = makeInst(
        block_, gate_, name, {.status = odb::dbPlacementStatus::PLACED});
    inst->findITerm("A")->connect(net);
    tst::RoutePath(net).on(layer_, {0, 0}).to({10000, 0}).build();
    return net;
  }

  odb::dbTechLayer* layer_{nullptr};
  odb::dbBlock* block_{nullptr};
  odb::dbMaster* gate_{nullptr};
  odb::dbMaster* diode_{nullptr};
};

TEST_F(AntennaMergeTest, StructuredResultsAndStableViolationSet)
{
  auto* first = routedNet("z_first");
  auto* second = routedNet("a_second");
  AntennaChecker checker(getDb(), getLogger());
  EXPECT_EQ(checker.checkAntennas(nullptr, 2), 2);
  EXPECT_EQ(checker.antennaViolationCount(), 2);
  EXPECT_EQ(checker.pinViolationCount(), 2);
  EXPECT_EQ(checker.violatingNets(), (std::vector<odb::dbNet*>{first, second}));

  const NetCheck result = checker.checkNet(first);
  EXPECT_EQ(result.net, first);
  EXPECT_TRUE(result.violated);
  ASSERT_EQ(result.pins.size(), 1);
  EXPECT_TRUE(result.pins.front().violated);
  ASSERT_EQ(result.pins.front().layers.size(), 1);
  const LayerCheck& layer = result.pins.front().layers.front();
  EXPECT_EQ(layer.layer, layer_);
  EXPECT_TRUE(layer.par.violated);
  EXPECT_GT(layer.par.actual, layer.par.required);
  EXPECT_DOUBLE_EQ(layer.par.required, 100.0);
  EXPECT_FALSE(layer.car.has_value());
  // A one-net query must not overwrite the last whole-design census.
  EXPECT_EQ(checker.violatingNets(), (std::vector<odb::dbNet*>{first, second}));
  EXPECT_EQ(checker.pinViolationCount(), 2);

  EXPECT_EQ(checker.checkAntennas(second), 1);
  EXPECT_EQ(checker.violatingNets(), (std::vector<odb::dbNet*>{second}));
  EXPECT_EQ(checker.pinViolationCount(), 1);
  tst::applyAntennaRule(layer_, {.par = 10000.0});
  EXPECT_EQ(checker.checkAntennas(), 0);
  EXPECT_TRUE(checker.violatingNets().empty());
  EXPECT_EQ(checker.pinViolationCount(), 0);
}

TEST_F(AntennaMergeTest, InertDiodeDiagnosticSurvivesStructuredReports)
{
  auto* net = routedNet("violating");
  auto* diode = makeInst(
      block_,
      diode_,
      "d1",
      {.location = {50000, 50000}, .status = odb::dbPlacementStatus::PLACED});
  diode->findITerm("D")->connect(net);
  AntennaChecker checker(getDb(), getLogger());
  getLogger()->redirectStringBegin();
  EXPECT_EQ(checker.checkAntennas(), 1);
  const std::string inert = getLogger()->redirectStringEnd();
  EXPECT_NE(inert.find("[WARNING ANT-0019]"), std::string::npos);
  EXPECT_NE(inert.find("violating (1 diode(s))"), std::string::npos);

  // The diode now physically touches the violating conductor. A repeat
  // check must clear the old no-diffusion diagnostic even if PAR still fails.
  diode->setLocation(5000, 0);
  getLogger()->redirectStringBegin();
  EXPECT_EQ(checker.checkAntennas(), 1);
  const std::string connected = getLogger()->redirectStringEnd();
  EXPECT_EQ(connected.find("[WARNING ANT-0019]"), std::string::npos);
}

TEST_F(AntennaMergeTest, UnroutedNetIsNamedAndExcludedFromViolationSet)
{
  auto* routed = routedNet("routed");
  auto* unrouted = routedNet("unrouted");
  odb::dbWire::destroy(unrouted->getWire());
  auto* diode = makeInst(block_, diode_, "d1");
  diode->findITerm("D")->connect(unrouted);
  AntennaChecker checker(getDb(), getLogger());
  getLogger()->redirectStringBegin();
  EXPECT_EQ(checker.checkAntennas(), 1);
  const std::string output = getLogger()->redirectStringEnd();
  EXPECT_NE(output.find("[WARNING ANT-0018]"), std::string::npos);
  EXPECT_NE(output.find("clean: unrouted"), std::string::npos);
  EXPECT_EQ(checker.violatingNets(), (std::vector<odb::dbNet*>{routed}));
  const NetCheck result = checker.checkNet(unrouted);
  EXPECT_EQ(result.net, unrouted);
  EXPECT_TRUE(result.pins.empty());
  EXPECT_FALSE(result.violated);
}

}  // namespace
}  // namespace ant
