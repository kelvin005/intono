#include <gtest/gtest.h>

#include <thread>

#include "ring.hpp"

using intono::SpscRing;

TEST(Ring, FifoOrderAndWraparound) {
  SpscRing<int> r(8);
  int v = -1;
  EXPECT_FALSE(r.pop(v));
  for (int round = 0; round < 5; ++round) {  // several wraps of the 8-slot buffer
    for (int i = 0; i < 6; ++i) ASSERT_TRUE(r.push(round * 10 + i));
    for (int i = 0; i < 6; ++i) {
      ASSERT_TRUE(r.pop(v));
      EXPECT_EQ(v, round * 10 + i);
    }
  }
  EXPECT_EQ(r.size(), 0u);
}

TEST(Ring, FullDropsNewestAndCounts) {
  SpscRing<int> r(4);
  for (int i = 0; i < 4; ++i) EXPECT_TRUE(r.push(i));
  EXPECT_FALSE(r.push(99));
  EXPECT_FALSE(r.push(100));
  EXPECT_EQ(r.dropped(), 2u);
  int v;
  for (int i = 0; i < 4; ++i) {  // the oldest four survive, in order
    ASSERT_TRUE(r.pop(v));
    EXPECT_EQ(v, i);
  }
}

TEST(Ring, ProducerConsumerThreadsKeepOrderWithoutLoss) {
  SpscRing<uint64_t> r(256);
  constexpr uint64_t kN = 2000000;
  std::thread prod([&] {
    for (uint64_t i = 0; i < kN;) if (r.push(i)) ++i;  // retry when full: lossless
  });
  uint64_t expect = 0, v;
  while (expect < kN) {
    if (r.pop(v)) {
      ASSERT_EQ(v, expect);
      ++expect;
    }
  }
  prod.join();
  EXPECT_EQ(r.size(), 0u);
}
