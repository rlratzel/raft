/*
 * Copyright (c) 2018-2021, NVIDIA CORPORATION.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include "../test_utils.h"
#include "distance_base.cuh"

namespace raft {
namespace distance {

template <typename DataType>
class DistanceLpUnexp
  : public DistanceTest<raft::distance::DistanceType::LpUnexpanded, DataType> {
};

const std::vector<DistanceInputs<float>> inputsf = {
  {0.001f, 1024, 1024, 32, true, 1234ULL, 4.0f},
  {0.001f, 1024, 32, 1024, true, 1234ULL, 3.0f},
  {0.001f, 32, 1024, 1024, true, 1234ULL, 4.0f},
  {0.003f, 1024, 1024, 1024, true, 1234ULL, 3.0f},
  {0.001f, 1024, 1024, 32, false, 1234ULL, 4.0f},
  {0.001f, 1024, 32, 1024, false, 1234ULL, 3.0f},
  {0.001f, 32, 1024, 1024, false, 1234ULL, 4.0f},
  {0.003f, 1024, 1024, 1024, false, 1234ULL, 3.0f},
};
typedef DistanceLpUnexp<float> DistanceLpUnexpF;
TEST_P(DistanceLpUnexpF, Result) {
  int m = params.isRowMajor ? params.m : params.n;
  int n = params.isRowMajor ? params.n : params.m;
  ASSERT_TRUE(raft::devArrMatch(dist_ref, dist, m, n,
                                raft::CompareApprox<float>(params.tolerance)));
}
INSTANTIATE_TEST_CASE_P(DistanceTests, DistanceLpUnexpF,
                        ::testing::ValuesIn(inputsf));

const std::vector<DistanceInputs<double>> inputsd = {
  {0.001, 1024, 1024, 32, true, 1234ULL, 4.0},
  {0.001, 1024, 32, 1024, true, 1234ULL, 3.0},
  {0.001, 32, 1024, 1024, true, 1234ULL, 4.0},
  {0.003, 1024, 1024, 1024, true, 1234ULL, 3.0},
  {0.001, 1024, 1024, 32, false, 1234ULL, 4.0},
  {0.001, 1024, 32, 1024, false, 1234ULL, 3.0},
  {0.001, 32, 1024, 1024, false, 1234ULL, 4.0},
  {0.003, 1024, 1024, 1024, false, 1234ULL, 3.0},
};
typedef DistanceLpUnexp<double> DistanceLpUnexpD;
TEST_P(DistanceLpUnexpD, Result) {
  int m = params.isRowMajor ? params.m : params.n;
  int n = params.isRowMajor ? params.n : params.m;
  ASSERT_TRUE(raft::devArrMatch(dist_ref, dist, m, n,
                                raft::CompareApprox<double>(params.tolerance)));
}
INSTANTIATE_TEST_CASE_P(DistanceTests, DistanceLpUnexpD,
                        ::testing::ValuesIn(inputsd));

}  // end namespace distance
}  // end namespace raft
