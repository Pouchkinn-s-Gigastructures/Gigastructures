Code
[[

static const bool GIGA_GLYPH[12][5][5] = {
	{
		{false, true,  true,  true,  false},
		{false, true,  false, true,  false},
		{false, true,  false, true,  false},
		{false, true,  false, true,  false},
		{false, true,  true,  true,  false}
	},
	{
		{false, true, true, false, false},
		{false, false, true, false, false},
		{false, false, true, false, false},
		{false, false, true, false, false},
		{false, true, true, true, false}
	},
	{
		{false, true, true, true, false},
		{false, false, false, true, false},
		{false, true, true, true, false},
		{false, true, false, false, false},
		{false, true, true, true, false}
	},
	{
		{false, true, true, true, false},
		{false, false, false, true, false},
		{false, false, true, true, false},
		{false, false, false, true, false},
		{false, true, true, true, false}
	},
	{
		{false, true, false, true, false},
		{false, true, false, true, false},
		{false, true, true, true, false},
		{false, false, false, true, false},
		{false, false, false, true, false}
	},
	{
		{false, true, true, true, false},
		{false, true, false, false, false},
		{false, true, true, true, false},
		{false, false, false, true, false},
		{false, true, true, true, false}
	},
	{
		{false, true, true, true, false},
		{false, true, false, false, false},
		{false, true, true, true, false},
		{false, true, false, true, false},
		{false, true, true, true, false}
	},
	{
		{false, true, true, true, false},
		{false, false, false, true, false},
		{false, false, false, true, false},
		{false, false, false, true, false},
		{false, false, false, true, false}
	},
	{
		{false, true, true, true, false},
		{false, true, false, true, false},
		{false, true, true, true, false},
		{false, true, false, true, false},
		{false, true, true, true, false}
	},
	{
		{false, true, true, true, false},
		{false, true, false, true, false},
		{false, true, true, true, false},
		{false, false, false, true, false},
		{false, true, true, true, false}
	},
	{
		{false, false, false, false, false},
		{false, false, false, false, false},
		{false, true, true, true, false},
		{false, false, false, false, false},
		{false, false, false, false, false}
	},
	{
		{false, false, false, false, false},
		{false, false, false, false, false},
		{false, false, false, false, false},
		{false, false, false, false, false},
		{false, false, true, false, false}
	},
};

bool giga_glyph_test(float2 pos, float2 glyphPos, int glyphID, int size) {
	float2 gMin = glyphPos;
	float2 gMax = glyphPos + float2(size,size)*5;

	if (pos.x >= gMin.x && pos.x <= gMax.x && pos.y >= gMin.y && pos.y <= gMax.y) {
		float2 diff = pos - glyphPos;
		float2 coord = floor(diff / size);

		if (coord.x >= 0 && coord.x < 5 && coord.y >= 0 && coord.y < 5) {
			int x = int(coord.x);
			int y = int(coord.y);

			return GIGA_GLYPH[glyphID][y][x];
			//return true;
		}
		//return true;
	}

	return false;
}

bool giga_glyph_number(float n, float2 pos, float2 drawPos, int digits, int decimals, int size) {
	bool negative = n < 0;
	n = abs(n);
	bool draw = false;
	int firstPower = digits - decimals;

	if(negative) {
		float2 glyphPos = drawPos + float2( size * 5 * -1, 0);
		draw = draw || giga_glyph_test(pos, glyphPos, 10, size);
	}

	if(decimals > 0) {
		float2 glyphPos = drawPos + float2( (size * 5 * firstPower) - (size * 2), 0);
		draw = draw || giga_glyph_test(pos, glyphPos, 11, size);
	}

	for( int i=0; i<digits; i++ ) {
		float2 glyphPos = drawPos + float2( size * 5 * i, 0);
		int power = firstPower - i;
		if (power <= 0) {
			glyphPos.x += size;
		}

		int digit = int(n / pow(10, power-1)) % 10;
		digit = clamp(digit,0,9);

		draw = draw || giga_glyph_test(pos, glyphPos, digit, size);
	}

	return draw;
}

bool giga_debug_number(float n, float2 pos, int2 drawPos) {
	float size = 10;
	return giga_glyph_number(n, pos, drawPos * size * float2(5,6), 10, 3, size);
}

bool giga_debug_float2(float2 n, float2 pos, int2 drawPos) {
	bool draw = false;
	draw = draw || giga_debug_number(n.x, pos, drawPos);
	draw = draw || giga_debug_number(n.y, pos, drawPos + int2(0,1));
	return draw;
}

bool giga_debug_float3(float3 n, float2 pos, int2 drawPos) {
	bool draw = false;
	draw = draw || giga_debug_number(n.x, pos, drawPos);
	draw = draw || giga_debug_number(n.y, pos, drawPos + int2(0,1));
	draw = draw || giga_debug_number(n.z, pos, drawPos + int2(0,2));
	return draw;
}

bool giga_debug_float4(float4 n, float2 pos, int2 drawPos) {
	bool draw = false;
	draw = draw || giga_debug_number(n.x, pos, drawPos);
	draw = draw || giga_debug_number(n.y, pos, drawPos + int2(0,1));
	draw = draw || giga_debug_number(n.z, pos, drawPos + int2(0,2));
	draw = draw || giga_debug_number(n.w, pos, drawPos + int2(0,3));
	return draw;
}

]]