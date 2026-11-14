#include "sim_clock.h"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>

#include <cmath>

using namespace godot;

void SimClock::_bind_methods() {
	ClassDB::bind_method(D_METHOD("advance", "delta"), &SimClock::advance);
	ClassDB::bind_method(D_METHOD("reset"), &SimClock::reset);

	ClassDB::bind_method(D_METHOD("set_ticks_per_second", "ticks_per_second"), &SimClock::set_ticks_per_second);
	ClassDB::bind_method(D_METHOD("get_ticks_per_second"), &SimClock::get_ticks_per_second);
	ClassDB::bind_method(D_METHOD("set_max_ticks_per_frame", "max_ticks_per_frame"), &SimClock::set_max_ticks_per_frame);
	ClassDB::bind_method(D_METHOD("get_max_ticks_per_frame"), &SimClock::get_max_ticks_per_frame);
	ClassDB::bind_method(D_METHOD("set_running", "running"), &SimClock::set_running);
	ClassDB::bind_method(D_METHOD("is_running"), &SimClock::is_running);
	ClassDB::bind_method(D_METHOD("get_tick"), &SimClock::get_tick);

	ADD_PROPERTY(PropertyInfo(Variant::INT, "ticks_per_second", PROPERTY_HINT_RANGE, "1,240,1"), "set_ticks_per_second", "get_ticks_per_second");
	ADD_PROPERTY(PropertyInfo(Variant::INT, "max_ticks_per_frame", PROPERTY_HINT_RANGE, "1,60,1"), "set_max_ticks_per_frame", "get_max_ticks_per_frame");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "running"), "set_running", "is_running");

	ADD_SIGNAL(MethodInfo("ticked", PropertyInfo(Variant::INT, "tick")));
}

void SimClock::_process(double p_delta) {
	advance(p_delta);
}

int SimClock::advance(double p_delta) {
	if (!running || !std::isfinite(p_delta) || p_delta <= 0.0) {
		return 0;
	}

	// Never add more time than one frame may use, so a huge delta cannot
	// overflow the accumulator. Anything beyond it would be dropped anyway.
	const double max_delta = static_cast<double>(max_ticks_per_frame) / ticks_per_second;
	accumulator_usec += static_cast<int64_t>(std::llround(MIN(p_delta, max_delta) * 1000000.0));

	int fired = 0;
	// The step is read on every pass so a rate change made from a `ticked`
	// handler applies from the next tick.
	while (fired < max_ticks_per_frame && accumulator_usec >= get_step_usec()) {
		accumulator_usec -= get_step_usec();
		tick++;
		fired++;
		emit_signal("ticked", tick);
	}

	// On a slow device, drop the backlog instead of trying to catch up, which
	// would make each following frame slower still.
	const int64_t step_usec = get_step_usec();
	if (accumulator_usec >= step_usec) {
		accumulator_usec %= step_usec;
	}
	return fired;
}

int64_t SimClock::get_step_usec() const {
	return 1000000 / ticks_per_second;
}

void SimClock::reset() {
	tick = 0;
	accumulator_usec = 0;
}

void SimClock::set_ticks_per_second(int p_ticks_per_second) {
	ticks_per_second = CLAMP(p_ticks_per_second, 1, 240);
}

int SimClock::get_ticks_per_second() const {
	return ticks_per_second;
}

void SimClock::set_max_ticks_per_frame(int p_max_ticks_per_frame) {
	max_ticks_per_frame = CLAMP(p_max_ticks_per_frame, 1, 60);
}

int SimClock::get_max_ticks_per_frame() const {
	return max_ticks_per_frame;
}

void SimClock::set_running(bool p_running) {
	running = p_running;
}

bool SimClock::is_running() const {
	return running;
}

int64_t SimClock::get_tick() const {
	return tick;
}
