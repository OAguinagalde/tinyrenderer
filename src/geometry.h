#ifndef __GEOMETRY_H__
#define __GEOMETRY_H__

#include <cmath>
#include <cassert>
#include <vector>

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

template <class t> struct Vec3;
template <class t> struct Vec2;

template <class t> struct Vec2 {
	union {
		struct {t u, v;};
		struct {t x, y;};
		t raw[2];
	};
	Vec2() : u(0), v(0) {}
	Vec2(t _u, t _v) : u(_u), v(_v) {}
	Vec2(Vec3<t> other) : u(other.x), v(other.y) {}
	inline Vec2<t> operator +(const Vec2<t> &V) const { return Vec2<t>(u+V.u, v+V.v); }
	inline Vec2<t> operator -(const Vec2<t> &V) const { return Vec2<t>(u-V.u, v-V.v); }
	inline Vec2<t> operator *(float f)          const { return Vec2<t>(u*f, v*f); }
	
	// dot product (represented by a dot ·) of 2 vectors A and B is a scalar N ( A · B = N )
	// sometimes called scalar product
	inline t       operator *(const Vec2<t> &v) const { return x*v.x + y*v.y; }
	
	// alternative version
	// inline t       operator *(const Vec2<t> &v) const { return (*this).magnitude() * v.magnitude() * std::cos(/*the angle between both vetors*/); }
	
	// also known as length, magnitude or norm
	// its represented like ||v||
	// Dont mistake it with the normalized or unit vector!
	inline float magnitude() const { return sqrt(x*x + y*y); }
	
	// V.normalized() == V / ||V||
	Vec2<t> normalized() const { return *this * (1 / magnitude()); }
	
	// cross product or vector product (represented by an x) of 2 vectors A and B is another vector C ( A x B = C )
	// C is exactly perpendicular (90 degrees) to the plane AB
	// the length of C will be the same as the area of the parallelogram formed by AB
	// that means that there has to be a 3rd dimension for the cross product to make sense
	// in this implementation we assume z = 0, meaning that the result will always be of type Vec3 (0, 0, x*v.y-y*v.x)
	// for that same reason, the magnitude of the resulting Vec3 will be just the value of the component z
	// inline Vec3<t> operator ^(const Vec2<t> &v) const { t z = 0; return Vec3<t>(y*z-z*v.y, z*v.x-x*z, x*v.y-y*v.x); }
	// taking into consideration the notes about the cross product above, it only makes sense to just use this and never the implementation above
	inline t       operator ^(const Vec2<t> &v) const { return x*v.y-y*v.x; }
	
	inline float cross_product_magnitude(const Vec2<t> &v) const { return x*v.y-y*v.x; }
	
};

template <class t> struct Vec3 {
	union {
		struct {t x, y, z;};
		struct {t u, v, w;};
		struct { t ivert, iuv, inorm; };
		t raw[3];
	};
	Vec3() : x(0), y(0), z(0) {}
	Vec3(t _x, t _y, t _z) : x(_x),y(_y),z(_z) {}
	// cross product
	inline Vec3<t> operator ^(const Vec3<t> &v) const { return Vec3<t>(y*v.z-z*v.y, z*v.x-x*v.z, x*v.y-y*v.x); }
	inline Vec3<t> operator +(const Vec3<t> &v) const { return Vec3<t>(x+v.x, y+v.y, z+v.z); }
	inline Vec3<t> operator -(const Vec3<t> &v) const { return Vec3<t>(x-v.x, y-v.y, z-v.z); }
	inline Vec3<t> operator *(float f)          const { return Vec3<t>(x*f, y*f, z*f); }
	// dot product
	inline t       operator *(const Vec3<t> &v) const { return x*v.x + y*v.y + z*v.z; }
	// returns the magnitude of a vector
	float norm () const { return std::sqrt(x*x+y*y+z*z); }
	Vec3<t> & normalize(t l=1) { *this = (*this)*(l/norm()); return *this; }
	Vec3<t> normalized(t l=1) { return (*this)*(l/norm()); }
};

typedef Vec2<float> Vec2f;
typedef Vec2<int>   Vec2i;
typedef Vec3<float> Vec3f;
typedef Vec3<int>   Vec3i;

struct BoundingBox {
	Vec2i tl, br;
};

//////////////////////////////////////////////////////////////////////////////////////////////

const int DEFAULT_ALLOC = 4;

class Matrix {
	std::vector<std::vector<float> > m;
	int rows, cols;
public:
	// Rows X Columns Matrix with values 0.f
	Matrix(int r = DEFAULT_ALLOC, int c = DEFAULT_ALLOC) : m(std::vector<std::vector<float> >(r, std::vector<float>(c, 0.f))), rows(r), cols(c) { };
	inline int nrows() { return rows; }
	inline int ncols() { return cols; }

	static Matrix identity(int dimensions = DEFAULT_ALLOC) {
		Matrix E(dimensions, dimensions);
		for (int i = 0; i < dimensions; i++) {
			for (int j = 0; j < dimensions; j++) {
				E[i][j] = (i == j ? 1.f : 0.f);
			}
		}
		return E;
	}

	std::vector<float>& operator[](const int i) {
		assert(i >= 0 && i < rows);
		return m[i];
	}

	Matrix operator*(const Matrix& a) {
		assert(cols == a.rows);
		Matrix result(rows, a.cols);
		for (int i = 0; i < rows; i++) {
			for (int j = 0; j < a.cols; j++) {
				result.m[i][j] = 0.f;
				for (int k = 0; k < cols; k++) {
					result.m[i][j] += m[i][k] * a.m[k][j];
				}
			}
		}
		return result;
	}

	Matrix operator+(const Matrix& a) {
		assert(cols == a.rows);
		Matrix result(rows, a.cols);
		for (int i = 0; i < rows; i++) {
			for (int j = 0; j < a.cols; j++) {
				result.m[i][j] = m[i][j] + a.m[i][j];
			}
		}
		return result;
	}

	Matrix transpose() {
		Matrix result(cols, rows);
		for (int i = 0; i < rows; i++)
			for (int j = 0; j < cols; j++)
				result[j][i] = m[i][j];
		return result;
	}

	static Matrix s(float scale_factor) {
		Matrix i = Matrix::identity();
		i[0][0] = scale_factor;
		i[1][1] = scale_factor;
		i[2][2] = scale_factor;
		return i;
	}

	static Matrix t(Vec3f translation) {
		Matrix i = Matrix::identity();
		i[0][3] = translation.raw[0];
		i[1][3] = translation.raw[1];
		i[2][3] = translation.raw[2];
		return i;
	}

	Matrix inverse() {
		assert(rows == cols);
		// augmenting the square matrix with the identity matrix of the same dimensions a => [ai]
		Matrix result(rows, cols * 2);
		for (int i = 0; i < rows; i++)
			for (int j = 0; j < cols; j++)
				result[i][j] = m[i][j];
		for (int i = 0; i < rows; i++)
			result[i][i + cols] = 1;
		// first pass
		for (int i = 0; i < rows - 1; i++) {
			// normalize the first row
			for (int j = result.cols - 1; j >= 0; j--)
				result[i][j] /= result[i][i];
			for (int k = i + 1; k < rows; k++) {
				float coeff = result[k][i];
				for (int j = 0; j < result.cols; j++) {
					result[k][j] -= result[i][j] * coeff;
				}
			}
		}
		// normalize the last row
		for (int j = result.cols - 1; j >= rows - 1; j--)
			result[rows - 1][j] /= result[rows - 1][rows - 1];
		// second pass
		for (int i = rows - 1; i > 0; i--) {
			for (int k = i - 1; k >= 0; k--) {
				float coeff = result[k][i];
				for (int j = 0; j < result.cols; j++) {
					result[k][j] -= result[i][j] * coeff;
				}
			}
		}
		// cut the identity matrix back
		Matrix truncate(rows, cols);
		for (int i = 0; i < rows; i++)
			for (int j = 0; j < cols; j++)
				truncate[i][j] = result[i][j + cols];
		return truncate;
	}
};

#endif //__GEOMETRY_H__
