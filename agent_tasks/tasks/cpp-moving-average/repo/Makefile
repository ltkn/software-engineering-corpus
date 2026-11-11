CXXFLAGS = -std=c++20 -Wall -Wextra -Werror -g -fsanitize=address,undefined
test: build/test_stats
	./build/test_stats
build/test_stats: src/stats.cpp src/stats.h test/test_stats.cpp
	mkdir -p build
	$(CXX) $(CXXFLAGS) -Isrc src/stats.cpp test/test_stats.cpp -o $@
.PHONY: test
