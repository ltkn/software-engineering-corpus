idf_component_register(SRCS "test_main.c" REQUIRES unity face_db)
target_link_libraries(${COMPONENT_LIB} PRIVATE m)
