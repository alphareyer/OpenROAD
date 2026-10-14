or_integration_tests(
  "ant"
  TESTS
    check_grt1
    repair_antennas_no_guides
  PASSFAIL_TESTS
    ant_api
    check_antennas_cmd
)

if(ENABLE_TESTS)
  add_subdirectory(cpp)
endif()
