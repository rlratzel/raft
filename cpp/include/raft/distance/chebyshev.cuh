/*
 * Copyright (c) 2021, NVIDIA CORPORATION.
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

#pragma once
#include <raft/distance/pairwise_distance_base.cuh>

namespace raft {
namespace distance {

/**
 * @brief the Chebyshev distance matrix calculation implementer
 *  It computes the following equation: cij = max(cij, op(ai-bj))
 * @tparam DataT          input data-type (for A and B matrices)
 * @tparam AccT           accumulation data-type
 * @tparam OutT           output data-type (for C and D matrices)
 * @tparam IdxT           index data-type
 * @tparam Veclen         number of k-elements loaded by each thread
                          for every LDG call. details in contractions.cuh
 * @tparam FinalLambda    final lambda called on final distance value
 * @tparam isRowMajor     true if input/output is row major,
                          false for column major
 * @param[in]       x input matrix
 * @param[in]       y input matrix
 * @param[in]       m number of rows of A and C/D
 * @param[in]       n number of rows of B and cols of C/D
 * @param[in]       k number of cols of A and B
 * @param[in]       lda leading dimension of A
 * @param[in]       ldb leading dimension of B
 * @param[in]       ldd leading dimension of C/D
 * @param[out]      dOutput output matrix
 * @param[in]       fin_op the final gemm epilogue lambda
 * @param[in]       stream cuda stream to launch work
 */
template <typename DataT, typename AccT, typename OutT, typename IdxT,
          int VecLen, typename FinalLambda, bool isRowMajor>
static void chebyshevImpl(const DataT *x, const DataT *y, IdxT m, IdxT n,
                          IdxT k, IdxT lda, IdxT ldb, IdxT ldd, OutT *dOutput,
                          FinalLambda fin_op, cudaStream_t stream) {
  typedef typename raft::linalg::Policy4x4<DataT, VecLen>::Policy RowPolicy;
  typedef typename raft::linalg::Policy4x4<DataT, VecLen>::ColPolicy ColPolicy;

  typedef
    typename std::conditional<isRowMajor, RowPolicy, ColPolicy>::type KPolicy;

  dim3 blk(KPolicy::Nthreads);

  // Accumulation operation lambda
  auto core_lambda = [] __device__(AccT & acc, DataT & x, DataT & y) {
    const auto diff = raft::L1Op<AccT, IdxT>()(x - y);
    acc = raft::myMax(acc, diff);
  };

  // epilogue operation lambda for final value calculation
  auto epilog_lambda = [] __device__(
                         AccT acc[KPolicy::AccRowsPerTh][KPolicy::AccColsPerTh],
                         DataT * regxn, DataT * regyn, IdxT gridStrideX,
                         IdxT gridStrideY) { return; };

  if (isRowMajor) {
    auto chebyshevRowMajor =
      pairwiseDistanceMatKernel<false, DataT, AccT, OutT, IdxT, KPolicy,
                                decltype(core_lambda), decltype(epilog_lambda),
                                FinalLambda, true>;
    dim3 grid = launchConfigGenerator<KPolicy>(m, n, KPolicy::SmemSize,
                                               chebyshevRowMajor);

    chebyshevRowMajor<<<grid, blk, KPolicy::SmemSize, stream>>>(
      x, y, nullptr, nullptr, m, n, k, lda, ldb, ldd, dOutput, core_lambda,
      epilog_lambda, fin_op);
  } else {
    auto chebyshevColMajor =
      pairwiseDistanceMatKernel<false, DataT, AccT, OutT, IdxT, KPolicy,
                                decltype(core_lambda), decltype(epilog_lambda),
                                FinalLambda, false>;
    dim3 grid = launchConfigGenerator<KPolicy>(m, n, KPolicy::SmemSize,
                                               chebyshevColMajor);
    chebyshevColMajor<<<grid, blk, KPolicy::SmemSize, stream>>>(
      x, y, nullptr, nullptr, m, n, k, lda, ldb, ldd, dOutput, core_lambda,
      epilog_lambda, fin_op);
  }

  CUDA_CHECK(cudaGetLastError());
}

template <typename DataT, typename AccT, typename OutT, typename IdxT,
          typename FinalLambda, bool isRowMajor>
void chebyshev(IdxT m, IdxT n, IdxT k, IdxT lda, IdxT ldb, IdxT ldd,
               const DataT *x, const DataT *y, OutT *dOutput,
               FinalLambda fin_op, cudaStream_t stream) {
  size_t bytesA = sizeof(DataT) * lda;
  size_t bytesB = sizeof(DataT) * ldb;
  if (16 % sizeof(DataT) == 0 && bytesA % 16 == 0 && bytesB % 16 == 0) {
    chebyshevImpl<DataT, AccT, OutT, IdxT, 16 / sizeof(DataT), FinalLambda,
                  isRowMajor>(x, y, m, n, k, lda, ldb, ldd, dOutput, fin_op,
                              stream);
  } else if (8 % sizeof(DataT) == 0 && bytesA % 8 == 0 && bytesB % 8 == 0) {
    chebyshevImpl<DataT, AccT, OutT, IdxT, 8 / sizeof(DataT), FinalLambda,
                  isRowMajor>(x, y, m, n, k, lda, ldb, ldd, dOutput, fin_op,
                              stream);
  } else {
    chebyshevImpl<DataT, AccT, OutT, IdxT, 1, FinalLambda, isRowMajor>(
      x, y, m, n, k, lda, ldb, ldd, dOutput, fin_op, stream);
  }
}

/**
 * @brief the chebyshev distance matrix calculation
 *  It computes the following equation: cij = max(cij, op(ai-bj))
 * @tparam InType input data-type (for A and B matrices)
 * @tparam AccType accumulation data-type
 * @tparam OutType output data-type (for C and D matrices)
 * @tparam FinalLambda user-defined epilogue lamba
 * @tparam Index_ Index type
 * @param[in] m number of rows of A and C/D
 * @param[in] n number of rows of B and cols of C/D
 * @param[in] k number of cols of A and B
 * @param[in] pA input matrix
 * @param[in] pB input matrix
 * @param[out] pD output matrix
 * @param[in] fin_op the final element-wise epilogue lambda
 * @param[in] stream cuda stream to launch work
 * @param[in] isRowMajor whether the input and output matrices are row major
 */
template <typename InType, typename AccType, typename OutType,
          typename FinalLambda, typename Index_ = int>
void chebyshevImpl(int m, int n, int k, const InType *pA, const InType *pB,
                   OutType *pD, FinalLambda fin_op, cudaStream_t stream,
                   bool isRowMajor) {
  typedef std::is_same<OutType, bool> is_bool;
  typedef typename std::conditional<is_bool::value, OutType, AccType>::type
    chebyshevOutType;
  Index_ lda, ldb, ldd;
  chebyshevOutType *pDcast = reinterpret_cast<chebyshevOutType *>(pD);
  if (isRowMajor) {
    lda = k, ldb = k, ldd = n;
    chebyshev<InType, AccType, chebyshevOutType, Index_, FinalLambda, true>(
      m, n, k, lda, ldb, ldd, pA, pB, pDcast, fin_op, stream);
  } else {
    lda = n, ldb = m, ldd = m;
    chebyshev<InType, AccType, chebyshevOutType, Index_, FinalLambda, false>(
      n, m, k, lda, ldb, ldd, pB, pA, pDcast, fin_op, stream);
  }
}
}  // namespace distance
}  // namespace raft
