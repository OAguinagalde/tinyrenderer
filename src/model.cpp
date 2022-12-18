#include <iostream>
#include <string>
#include <fstream>
#include <sstream>
#include <vector>
#include "model.h"

Model::Model(const char *filename) : verts_(), text_verts_(), text_vert_normals_(), faces_() {
    std::ifstream in;
    in.open (filename, std::ifstream::in);
    if (in.fail()) return;
    std::string line;
    while (!in.eof()) {
        std::getline(in, line);
        std::istringstream iss(line.c_str());
        char trash;
        // If the line is a "vertex" save its values
        if (!line.compare(0, 2, "v ")) {
            iss >> trash;
            Vec3f v;
            for (int i=0;i<3;i++) iss >> v.raw[i];
            verts_.push_back(v);
        }
        // If the line is a "texture vertex" save its values
        else if (!line.compare(0, 3, "vt ")) {
            iss >> trash >> trash;
            Vec2f vt;
            for (int i=0;i<2;i++) iss >> vt.raw[i];
            text_verts_.push_back(vt);
        }
        // If the line is a "vertex normal" save its values
        else if (!line.compare(0, 3, "vn ")) {
            iss >> trash >> trash;
            Vec3f vn;
            for (int i=0;i<3;i++) iss >> vn.raw[i];
            text_vert_normals_.push_back(vn);
        }
        // If the line is a "face" save the index (the first int), we don't care about the rest
        else if (!line.compare(0, 2, "f ")) {
            std::vector<int> location_vertex_indices;
            std::vector<int> texture_vertex_indices;
            std::vector<int> vertex_normal_indices;
            int location_idx, text_idx, normal_idx;
            iss >> trash;
            // This is basically:
            // While this set of operations work ...{
            //     extract an int (save it in a vector),   Notes Oscar: I believe this is the index to the location vertex data
            //     extract a character (don't care),
            //     extract an int (don't care),            Notes Oscar: I believe this is the index to the texture vertex data
            //     extract a character (don't care),
            //     extract an int (don't care)
            // }

            // Notes Oscar: If you check the obj file, they come in trios, because 1 facet is made out of 3 vertices. example:
            // f loc_idx/text_idx/normal_idx loc_idx/text_idx/normal_idx loc_idx/text_idx/normal_idx
            // so this while will (should) iterate 3 times per facet
            while (iss >> location_idx >> trash >> text_idx >> trash >> normal_idx) {
                // in wavefront obj all indices start at 1, not zero
                location_idx--;
                text_idx--;
                normal_idx--;
                location_vertex_indices.push_back(location_idx);
                texture_vertex_indices.push_back(text_idx);
                vertex_normal_indices.push_back(normal_idx);
            }

            // Vertex contains both location and texture data
            Vertex vertex;
            vertex.location = location_vertex_indices;
            vertex.texture = texture_vertex_indices;
            vertex.normals = vertex_normal_indices;
            
            faces_.push_back(vertex);
        }
    }
    std::cerr << "# v# " << verts_.size() << " f# "  << faces_.size() << std::endl;
}

Model::Model() : verts_(), text_verts_(), faces_() {

    verts_.push_back(Vec3f(-0.90,-0.90,-0.90));
    verts_.push_back(Vec3f(0.90,-0.90, 0.90));
    verts_.push_back(Vec3f(0.90, 0.90, 0.90));
    verts_.push_back(Vec3f(-0.90, 0.90, -0.90));
    
    text_verts_.push_back(Vec2f(0, 0));
    text_verts_.push_back(Vec2f(1, 0));
    text_verts_.push_back(Vec2f(1, 1));
    text_verts_.push_back(Vec2f(0, 1));

    {
        std::vector<int> location_vertex_indices;
        std::vector<int> texture_vertex_indices;

        location_vertex_indices.push_back(0);
        location_vertex_indices.push_back(1);
        location_vertex_indices.push_back(2);

        texture_vertex_indices.push_back(0);
        texture_vertex_indices.push_back(1);
        texture_vertex_indices.push_back(2);

        Vertex vertex;
        vertex.location = location_vertex_indices;
        vertex.texture = texture_vertex_indices;

        faces_.push_back(vertex);
    }

    {
        std::vector<int> location_vertex_indices;
        std::vector<int> texture_vertex_indices;
        
        location_vertex_indices.push_back(0);
        location_vertex_indices.push_back(2);
        location_vertex_indices.push_back(3);
        
        texture_vertex_indices.push_back(0);
        texture_vertex_indices.push_back(2);
        texture_vertex_indices.push_back(3);

        Vertex vertex;
        vertex.location = location_vertex_indices;
        vertex.texture = texture_vertex_indices;

        faces_.push_back(vertex);
    }
}

Model::~Model() {
}

int Model::nverts() {
    return (int)verts_.size();
}

int Model::nfaces() {
    return (int)faces_.size();
}

Vertex Model::face(int idx) {
    return faces_[idx];
}

Vec3f Model::vert(int i) {
    return verts_[i];
}

Vec2f Model::text(int i) {
    return text_verts_[i];
}

Vec3f Model::normal(int i) {
    return text_vert_normals_[i];
}
