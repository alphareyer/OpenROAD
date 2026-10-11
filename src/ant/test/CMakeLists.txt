or_integration_tests(
  "ant"
  TESTS
    ant_check
    ant_report
    check_api1
    check_disjoint_stubs
    check_drt1
    check_grt1
    check_output_pin_bridge
    repair_antennas_no_guides
)

add_executable(TestAntennaMerge cpp/TestAntennaMerge.cpp)
target_link_libraries(TestAntennaMerge
  ant_lib
  tst_base
  tst_physical
  GTest::gtest_main
)
gtest_discover_tests(TestAntennaMerge)
add_dependencies(build_and_test TestAntennaMerge)
