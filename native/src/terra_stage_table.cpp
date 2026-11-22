// The stage table's region rules (see terra_stage_table.h): the one place a stage's region is made
// from its row, so the derive loop never names a halo.
#include "terra_stage_table.h"

namespace terra {

Dirty stage_read_change(const StageDef &s, const Dirty *changed, const Grid &g) {
	Dirty d;
	d.init(g);
	for (int a = 0; a < A_COUNT; a++) {
		if ((s.reads & bit(a)) && ARRAYS[a].kind == K_SAMPLES) {
			d.merge(changed[a], g);
		}
	}
	return d;
}

Dirty stage_region(const StageDef &s, const Dirty *changed, const Dirty &own, const Grid &g) {
	Dirty d = stage_read_change(s, changed, g).dilate(s.halo > 0 ? s.halo : 0, g);
	for (int a = 0; a < A_COUNT; a++) {
		if ((s.reads & bit(a)) && ARRAYS[a].kind != K_SAMPLES) {
			d.merge(changed[a], g);
		}
	}
	d.merge(own, g);
	return d;
}

} // namespace terra
