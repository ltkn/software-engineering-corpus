idf_component_register(SRCS "test_main.c" REQUIRES unity csi_motion)
target_link_libraries(${COMPONENT_LIB} PRIVATE m)
