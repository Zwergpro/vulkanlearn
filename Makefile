


compile_shaders:
	mkdir -p bin/shaders/ || true
	glslc src/shaders/shader.vert -o bin/shaders/vert.spv
	glslc src/shaders/shader.frag -o bin/shaders/frag.spv
