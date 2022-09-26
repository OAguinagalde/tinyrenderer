#ifndef __GEOMETRY_H__
#define __GEOMETRY_H__

#include <cmath>

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
	
	template <class > friend std::ostream& operator<<(std::ostream& s, Vec2<t>& v);
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
	float norm () const { return std::sqrt(x*x+y*y+z*z); }
	Vec3<t> & normalize(t l=1) { *this = (*this)*(l/norm()); return *this; }
	Vec3<t> normalized(t l=1) { return (*this)*(l/norm()); }
	template <class > friend std::ostream& operator<<(std::ostream& s, Vec3<t>& v);
};

typedef Vec2<float> Vec2f;
typedef Vec2<int>   Vec2i;
typedef Vec3<float> Vec3f;
typedef Vec3<int>   Vec3i;

struct BoundingBox {
	Vec2i tl, br;
};

template <class t> std::ostream& operator<<(std::ostream& s, Vec2<t>& v) {
	s << "(" << v.x << ", " << v.y << ")\n";
	return s;
}

template <class t> std::ostream& operator<<(std::ostream& s, Vec3<t>& v) {
	s << "(" << v.x << ", " << v.y << ", " << v.z << ")\n";
	return s;
}

#endif //__GEOMETRY_H__
