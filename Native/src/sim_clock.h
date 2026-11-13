#pragma once

#include <godot_cpp/classes/node.hpp>

#include <cstdint>

namespace godot {

// Fixed-step simulation clock. It turns variable frame time into a steady
// stream of integer ticks, so turn order, combat and network lockstep can run
// on the same tick count on every device. Time is kept in whole microseconds
// to avoid floating-point drift between platforms.
class SimClock : public Node {
	GDCLASS(SimClock, Node)

	int ticks_per_second = 20;
	int max_ticks_per_frame = 5;
	bool running = true;
	int64_t tick = 0;
	int64_t accumulator_usec = 0;

protected:
	static void _bind_methods();

public:
	void _process(double p_delta) override;

	int advance(double p_delta);
	void reset();

	void set_ticks_per_second(int p_ticks_per_second);
	int get_ticks_per_second() const;
	void set_max_ticks_per_frame(int p_max_ticks_per_frame);
	int get_max_ticks_per_frame() const;
	void set_running(bool p_running);
	bool is_running() const;
	int64_t get_tick() const;
};

} // namespace godot
