#ifndef __MODEL_H__
#define __MODEL_H__

#include <vector>
#include "geometry.h"

struct Vertex {
	std::vector<int> location; // 3 locations indices
	std::vector<int> texture; // 3 texture indices
};

class Model {
private:
	// the location data of each vertex in the model
	std::vector<Vec3f> verts_;
	// the texture data of each vertex in the model
	std::vector<Vec2f> text_verts_;
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
	Vertex face(int idx);
};

#endif //__MODEL_H__
