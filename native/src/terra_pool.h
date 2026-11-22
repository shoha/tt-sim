// The derive's worker pool (from spike terraform-s2-cpu): a fixed set of threads that run one
// indexed job at a time, the caller joining in. A stage splits by tile; the bits never depend on
// the thread count.
#pragma once

#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <functional>
#include <mutex>
#include <thread>
#include <vector>

namespace terra {

/// A fixed set of worker threads that run one indexed job at a time; the caller joins in.
class Pool {
public:
	explicit Pool(int n) {
		for (int i = 0; i < n; i++) {
			workers.emplace_back([this] { loop(); });
		}
	}
	~Pool() {
		{
			std::lock_guard<std::mutex> lk(m);
			quit = true;
		}
		cv.notify_all();
		for (std::thread &t : workers) {
			t.join();
		}
	}
	void run(int count, const std::function<void(int)> &fn) {
		if (count <= 0) {
			return;
		}
		if (workers.empty() || count == 1) {
			for (int i = 0; i < count; i++) {
				fn(i);
			}
			return;
		}
		{
			std::lock_guard<std::mutex> lk(m);
			job = &fn;
			total = count;
			next.store(0);
			pending = int(workers.size());
			gen++;
		}
		cv.notify_all();
		work();
		std::unique_lock<std::mutex> lk(m);
		done.wait(lk, [&] { return pending == 0; });
		job = nullptr;
	}

private:
	void work() {
		int i;
		while ((i = next.fetch_add(1)) < total) {
			(*job)(i);
		}
	}
	void loop() {
		uint64_t seen = 0;
		while (true) {
			{
				std::unique_lock<std::mutex> lk(m);
				cv.wait(lk, [&] { return quit || gen != seen; });
				if (quit) {
					return;
				}
				seen = gen;
			}
			work();
			std::lock_guard<std::mutex> lk(m);
			if (--pending == 0) {
				done.notify_one();
			}
		}
	}
	std::vector<std::thread> workers;
	std::mutex m;
	std::condition_variable cv, done;
	const std::function<void(int)> *job = nullptr;
	std::atomic<int> next{ 0 };
	int total = 0;
	int pending = 0;
	uint64_t gen = 0;
	bool quit = false;
};

} // namespace terra
