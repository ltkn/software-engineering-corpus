idf_component_register(SRCS "face_db.c" INCLUDE_DIRS "include" REQUIRES esp_common)
# libm is linked implicitly on the chips but not on the linux host target.
target_link_libraries(${COMPONENT_LIB} PRIVATE m)
