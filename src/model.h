#ifndef __MODEL_H__
#define __MODEL_H__

#include <vector>
#include "geometry.h"

struct Vertex {
	std::vector<int> location; // 3 locations indices
	std::vector<int> texture; // 3 texture indices
	std::vector<int> normals; // 3 normal indices
};

class Model {
private:
	// the location data of each vertex in the model
	std::vector<Vec3f> verts_;
	// the texture data of each vertex in the model
	std::vector<Vec2f> text_verts_;
	// the vertex normal data of each vertex in the model
	std::vector<Vec3f> text_vert_normals_;
	// each facet represents a group of 3 vertices (aka triangle)
	std::vector<Vertex> faces_;
public:
	// for debugging only, represents a quad
	Model();
	Model(const char* filename);
	~Model();
	int nverts();
	int nfaces();
	Vec3f vert(int i);
	Vec2f text(int i);
	Vec3f normal(int i);
	Vertex face(int idx);

	int get_vertex_buffer_size() {
		return nfaces() * 3 * 8 * sizeof(float);
	}
	
	// returns a vertex buffer with layout:
	// { location_x, location_y, location_z, text_u, text_v, normal_x, normal_y, normal_z } * 3 * tirangle_count
	// buffer must have enough space for: triangle_count * 3 * 8 * sizeof(float)
	void load_vertex_buffer(float* buffer) {

		for (int tri = 0; tri < nfaces(); tri++) {

			std::vector<int> location_indexes = face(tri).location;
			std::vector<int> uv_indexes = face(tri).texture;
			std::vector<int> normal_indexes = face(tri).normals;

			float* triangle_vertices = &buffer[tri*8*3];

			for (int j = 0; j < 3; j++) {
				
				triangle_vertices[8 * j + 0] = vert(location_indexes[j]).x;
				triangle_vertices[8 * j + 1] = vert(location_indexes[j]).y;
				triangle_vertices[8 * j + 2] = vert(location_indexes[j]).z;
				triangle_vertices[8 * j + 3] = text(uv_indexes[j]).u;
				triangle_vertices[8 * j + 4] = text(uv_indexes[j]).v;
				triangle_vertices[8 * j + 5] = normal(normal_indexes[j]).x;
				triangle_vertices[8 * j + 6] = normal(normal_indexes[j]).y;
				triangle_vertices[8 * j + 7] = normal(normal_indexes[j]).z;
				
			}
		}
	}
};

#endif //__MODEL_H__
