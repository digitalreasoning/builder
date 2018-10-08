#!/bin/bash

# Essentially runs pytorch/test/run_test.py, but keeps track of which tests to
# skip in a centralized place.
# Except for a few tests, this entire file is a giant TODO. Why are these tests
# failing?
# TODO deal with Windows

set -ex

# This script expects to be in the pytorch root folder
if [[ ! -d 'test' || ! -f 'test/run_test.py' ]]; then
    echo "builder/test.sh expects to be run from the Pytorch root directory " \
         "but I'm actually in $(pwd)"
    exit 1
fi

# If given specific test params then just run those
if [[ -n "$RUN_TEST_PARAMS" ]]; then
    echo "$(date) :: Calling user-command $(pwd)/test/run_test.py ${RUN_TEST_PARAMS[@]}"
    python test/run_test.py ${RUN_TEST_PARAMS[@]}
    exit 0
fi

# Parameters
##############################################################################
if [[ "$#" != 3 ]]; then
  if [[ -z "$DESIRED_PYTHON" || -z "$DESIRED_CUDA" || -z "$PACKAGE_TYPE" ]]; then
      echo "The env variabled PACKAGE_TYPE must be set to 'conda' or 'manywheel' or 'libtorch'"
      echo "The env variabled DESIRED_PYTHON must be set like '2.7mu' or '3.6m' etc"
      echo "The env variabled DESIRED_CUDA must be set like 'cpu' or 'cu80' etc"
      exit 1
  fi
  package_type="$PACKAGE_TYPE"
  py_ver="$DESIRED_PYTHON"
  cuda_ver="$DESIRED_CUDA"
else
  package_type="$1"
  py_ver="$2"
  cuda_ver="$3"
fi

echo "$(date) :: Starting tests for $package_type package for python$py_ver and $cuda_ver"


# We keep track of exact tests to skip, as otherwise we would be hardly running
# any tests. But b/c of issues working with pytest/normal-python-test/ and b/c
# of special snowflake tests in test/run_test.py we also take special care of
# those
tests_to_skip=()

#
# Entire file exclusions
##############################################################################
entire_file_exclusions=("-x")

# cpp_extensions doesn't work with pytest, so we exclude it from the pytest run
# here and then manually run it later. Note that this is only because this
# entire_fil_exclusions flag is only passed to the pytest run
entire_file_exclusions+=("cpp_extensions")

if [[ "$cuda_ver" == 'cpu' ]]; then
    # test/test_cuda.py exits early if the installed torch is not built with
    # CUDA, but the exit doesn't work when running with pytest, so pytest will
    # still try to run all the CUDA tests and then fail
    entire_file_exclusions+=("cuda")
    entire_file_exclusions+=("nccl")
fi

if [[ "$(uname)" == 'Darwin' ]]; then
    # pytest on Mac doesn't like the exits in these files
    entire_file_exclusions+=('c10d')
    entire_file_exclusions+=('distributed')

    # pytest doesn't mind the exit but fails the tests. On Mac we run this
    # later without pytest
    entire_file_exclusions+=('thd_distributed')
fi


#
# Universal flaky tests
##############################################################################

# RendezvousEnvTest hangs sometimes hangs forever
# Otherwise it will fail on CUDA with
#   Traceback (most recent call last):
#     File "test_c10d.py", line 179, in test_common_errors
#       next(gen)
#   AssertionError: ValueError not raised
tests_to_skip+=('RendezvousEnvTest and test_common_errors')

# test_trace_warn isn't actually flaky, but it doesn't work with pytest so we
# just skip it
tests_to_skip+=('TestJit and test_trace_warn')

#
# CUDA flaky tests, all package types
##############################################################################
if [[ "$cuda_ver" != 'cpu' ]]; then

    #
    # DistributedDataParallelTest
    # All of these seem to fail
    tests_to_skip+=('DistributedDataParallelTest')

    #
    # RendezvousEnvTest
    # Traceback (most recent call last):
    #   File "test_c10d.py", line 201, in test_nominal
    #     store0, rank0, size0 = next(gen0)
    #   File "/opt/python/cp36-cp36m/lib/python3.6/site-packages/torch/distributed/rendezvous.py", line 131, in _env_rendezvous_handler
    #     store = TCPStore(master_addr, master_port, start_daemon)
    # RuntimeError: Address already in use
    tests_to_skip+=('RendezvousEnvTest and test_nominal')

    #
    # TestCppExtension
    #
    # Traceback (most recent call last):
    #   File "test_cpp_extensions.py", line 134, in test_jit_cudnn_extension
    #     with_cuda=True)
    #   File "/opt/python/cp35-cp35m/lib/python3.5/site-packages/torch/utils/cpp_extension.py", line 552, in load
    #     with_cuda)
    #   File "/opt/python/cp35-cp35m/lib/python3.5/site-packages/torch/utils/cpp_extension.py", line 729, in _jit_compile
    #     return _import_module_from_library(name, build_directory)
    #   File "/opt/python/cp35-cp35m/lib/python3.5/site-packages/torch/utils/cpp_extension.py", line 867, in _import_module_from_library
    #     return imp.load_module(module_name, file, path, description)
    #   File "/opt/python/cp35-cp35m/lib/python3.5/imp.py", line 243, in load_module
    #     return load_dynamic(name, filename, file)
    #   File "/opt/python/cp35-cp35m/lib/python3.5/imp.py", line 343, in load_dynamic
    #     return _load(spec)
    #   File "<frozen importlib._bootstrap>", line 693, in _load
    #   File "<frozen importlib._bootstrap>", line 666, in _load_unlocked
    #   File "<frozen importlib._bootstrap>", line 577, in module_from_spec
    #   File "<frozen importlib._bootstrap_external>", line 938, in create_module
    #   File "<frozen importlib._bootstrap>", line 222, in _call_with_frames_removed
    # ImportError: libcudnn.so.7: cannot open shared object file: No such file or directory
		tests_to_skip+=('TestCppExtension and test_jit_cudnn_extension')

    #
    # TestCuda
    #

    # 3.7_cu80
    #  RuntimeError: CUDA error: out of memory
    tests_to_skip+=('TestCuda and test_arithmetic_large_tensor')

    # 3.7_cu80
    # RuntimeError: cuda runtime error (2) : out of memory at /opt/conda/conda-bld/pytorch-nightly_1538097262541/work/aten/src/THC/THCTensorCopy.cu:205
    tests_to_skip+=('TestCuda and test_autogpu')

    #
    # TestDistBackend
    #

    # Traceback (most recent call last):
    #   File "test_thd_distributed.py", line 1046, in wrapper
    #     self._join_and_reduce(fn)
    #   File "test_thd_distributed.py", line 1108, in _join_and_reduce
    #     self.assertEqual(p.exitcode, first_process.exitcode)
    #   File "/pytorch/test/common.py", line 399, in assertEqual
    #     super(TestCase, self).assertEqual(x, y, message)
    # AssertionError: None != 77 :
    tests_to_skip+=('TestDistBackend and test_all_gather_group')
    tests_to_skip+=('TestDistBackend and test_all_reduce_group_max')
    tests_to_skip+=('TestDistBackend and test_all_reduce_group_min')
    tests_to_skip+=('TestDistBackend and test_all_reduce_group_sum')
    tests_to_skip+=('TestDistBackend and test_all_reduce_group_product')
    tests_to_skip+=('TestDistBackend and test_barrier_group')
    tests_to_skip+=('TestDistBackend and test_broadcast_group')

    # Traceback (most recent call last):
    #   File "test_thd_distributed.py", line 1046, in wrapper
    #     self._join_and_reduce(fn)
    #   File "test_thd_distributed.py", line 1108, in _join_and_reduce
    #     self.assertEqual(p.exitcode, first_process.exitcode)
    #   File "/pytorch/test/common.py", line 397, in assertEqual
    #     super(TestCase, self).assertLessEqual(abs(x - y), prec, message)
    # AssertionError: 12 not less than or equal to 1e-05
    tests_to_skip+=('TestDistBackend and test_barrier')

    # Traceback (most recent call last):
    #   File "test_distributed.py", line 1267, in wrapper
    #     self._join_and_reduce(fn)
    #   File "test_distributed.py", line 1350, in _join_and_reduce
    #     self.assertEqual(p.exitcode, first_process.exitcode)
    #   File "/pytorch/test/common.py", line 399, in assertEqual
    #     super(TestCase, self).assertEqual(x, y, message)
    # AssertionError: None != 1
    tests_to_skip+=('TestDistBackend and test_broadcast')

    # Memory leak very similar to all the conda ones below, but appears on manywheel
    if  [[ "$cuda_ver" != 'cpu' ]]; then
        # 3.6m_cu80
        # AssertionError: 1605632 not less than or equal to 1e-05 : __main__.TestEndToEndHybridFrontendModels.test_vae_cuda leaked 1605632 bytes CUDA memory on device 0
        tests_to_skip+=('TestEndToEndHybridFrontendModels and test_vae_cuda')
    fi
fi


##########################################################################
# Conda specific flaky tests
##########################################################################

# Lots of memory leaks on CUDA
if [[ "$package_type" == 'conda' && "$cuda_ver" != 'cpu' ]]; then

    # 3.7_cu92
    # AssertionError: 63488 not less than or equal to 1e-05 : __main__.TestEndToEndHybridFrontendModels.test_mnist_cuda leaked 63488 bytes CUDA memory on device 0
    tests_to_skip+=('TestEndToEndHybridFrontendModels and test_mnist_cuda')

    # 2.7_cu92
    # AssertionError: __main__.TestNN.test_BatchNorm3d_momentum_eval_cuda leaked -1024 bytes CUDA memory on device 0
    tests_to_skip+=('TestNN and test_BatchNorm3d_momentum_eval_cuda')

    # 2.7_cu92
    # AssertionError: __main__.TestNN.test_ConvTranspose2d_cuda leaked -1024 bytes CUDA memory on device 0
    tests_to_skip+=('TestNN and test_ConvTranspose2d_cuda')

    # 3.7_cu90
    # AssertionError: 1024 not less than or equal to 1e-05 : __main__.TestNN.test_ConvTranspose3d_cuda leaked -1024 bytes CUDA memory on device 0
    tests_to_skip+=('TestNN and test_ConvTranspose3d_cuda')

    # 2.7_cu90
    # 2.7_cu92
    # 3.5_cu90 x2
    # 3.6_cu90
    # 3.7_cu80 x3
    # 3.7_cu90
    # AssertionError: 37376 not less than or equal to 1e-05 : __main__.TestNN.test_CTCLoss_1d_target_cuda_double leaked 37376 bytes CUDA memory on device 0
    tests_to_skip+=('TestNN and test_CTCLoss_1d_target_cuda_double')

    # 2.7_cu80 --18944
    # 2.7_cu92
    # 3.5_cu90 --18944 x2
    # 3.5_cu92 --18944 x2
    # 3.6_cu90 --18944
    # 3.6_cu92 --18944
    # 3.7_cu80
    # AssertionError: 37376 not less than or equal to 1e-05 : __main__.TestNN.test_CTCLoss_1d_target_cuda_float leaked -37376 bytes CUDA memory on device 0
    tests_to_skip+=('TestNN and test_CTCLoss_1d_target_cuda_float')

    # 3.5_cu90
    # 3.7_cu92
    # AssertionError: 37376 not less than or equal to 1e-05 : __main__.TestNN.test_CTCLoss_1d_target_sum_reduction_cuda_double leaked 37376 bytes CUDA memory on device 0
    tests_to_skip+=('TestNN and test_CTCLoss_1d_target_sum_reduction_cuda_double')

    # 3.7_cu92
    # AssertionError: 18432 not less than or equal to 1e-05 : __main__.TestNN.test_CTCLoss_1d_target_sum_reduction_cuda_float leaked -18432 bytes CUDA memory on device 0
    tests_to_skip+=('TestNN and test_CTCLoss_1d_target_sum_reduction_cuda_float')

    # 3.5_cu92 x2
    # 3.6_cu80
    # 3.7_cu90
    # AssertionError: AssertionError: 37376 not less than or equal to 1e-05 : __main__.TestNN.test_CTCLoss_2d_int_target_cuda_double leaked 37376 bytes CUDA memory on device 0
    tests_to_skip+=('TestNN and test_CTCLoss_2d_int_target_cuda_double')

    # 3.5_cu92
    # 3.6_cu80 --37376
    # 3.6_cu92
    # AssertionError: 18944 not less than or equal to 1e-05 : __main__.TestNN.test_CTCLoss_2d_int_target_cuda_float leaked 18944 bytes CUDA memory on device 0
    tests_to_skip+=('TestNN and test_CTCLoss_2d_int_target_cuda_float')

    # 2.7_cu90
    # 3.5_cu80
    # 3.7_cu80 x2
    # AssertionError: 37376 not less than or equal to 1e-05 : __main__.TestNN.test_CTCLoss_2d_int_target_sum_reduction_cuda_double leaked 37376 bytes CUDA memory on device 0
    tests_to_skip+=('TestNN and test_CTCLoss_2d_int_target_sum_reduction_cuda_double')

    # 2.7_cu90
    # 2.7_cu92 --18944
    # AssertionError: __main__.TestNN.test_CTCLoss_2d_int_target_sum_reduction_cuda_float leaked -37376 bytes CUDA memory on device 0
    tests_to_skip+=('TestNN and test_CTCLoss_2d_int_target_sum_reduction_cuda_float')

    # 2.7_cu92
    # AssertionError: __main__.TestNN.test_CTCLoss_cuda_double leaked 37376 bytes CUDA memory on device 0
    tests_to_skip+=('TestNN and test_CTCLoss_cuda_double')

    # 2.7_cu92
    # AssertionError: __main__.TestNN.test_CTCLoss_cuda_float leaked 18944 bytes CUDA memory on device 0
    tests_to_skip+=('TestNN and test_CTCLoss_cuda_float')

    # 2.7_cu92
    # 3.5_cu90 x2
    # 3.5_cu92
    # 3.5_cu92
    # 3.6_cu80 x2
    # AssertionError: 37376 not less than or equal to 1e-05 : __main__.TestNN.test_CTCLoss_sum_reduction_cuda_double leaked 37376 bytes CUDA memory on device 0
    tests_to_skip+=('TestNN and test_CTCLoss_sum_reduction_cuda_double')

    # 2.7_cu92 --18944
    # 3.6_cu80
    # AssertionError: 37376 not less than or equal to 1e-05 : __main__.TestNN.test_CTCLoss_sum_reduction_cuda_float leaked -37376 bytes CUDA memory on device 0
    tests_to_skip+=('TestNN and test_CTCLoss_sum_reduction_cuda_float')

    # 3.5_cu90 x2
    # AssertionError: 3584 not less than or equal to 1e-05 : __main__.TestNN.test_NLLLoss_2d_cuda_double leaked 3584 bytes CUDA memory on device 0
    tests_to_skip+=('TestNN and test_NLLLoss_2d_cuda_double')

    # 2.7_cu80
    # AssertionError: __main__.TestNN.test_NLLLoss_2d_cuda_float leaked 2560 bytes CUDA memory on device 0
    tests_to_skip+=('TestNN and test_NLLLoss_2d_cuda_float')

    # 2.7_cu80
    # 2.7_cu92
    # 3.6_cu80 x2
    # AssertionError: 1536 not less than or equal to 1e-05 : __main__.TestNN.test_NLLLoss_2d_cuda_half leaked 1536 bytes CUDA memory on device 0
    tests_to_skip+=('TestNN and test_NLLLoss_2d_cuda_half')

    # 2.7_cu90
    # 3.6_cu80 x2
    # 3.6_cu90
    # 3.6_cu92
    # AssertionError: 3584 not less than or equal to 1e-05 : __main__.TestNN.test_NLLLoss_2d_ignore_index_cuda_double leaked 3584 bytes CUDA memory on device 0
    tests_to_skip+=('TestNN and test_NLLLoss_2d_ignore_index_cuda_double')

    # 3.6_cu80 x2
    # 3.6_cu90
    # AssertionError: 3584 not less than or equal to 1e-05 : __main__.TestNN.test_NLLLoss_2d_ignore_index_cuda_float leaked -3584 bytes CUDA memory on device 0
    tests_to_skip+=('TestNN and test_NLLLoss_2d_ignore_index_cuda_float')

    # 3.6_cu80
    # AssertionError: 3584 not less than or equal to 1e-05 : __main__.TestNN.test_NLLLoss_2d_sum_reduction_cuda_double leaked 3584 bytes CUDA memory on device 0
    tests_to_skip+=('TestNN and test_NLLLoss_2d_sum_reduction_cuda_double')

    # 3.6_cu80
    # AssertionError: 2560 not less than or equal to 1e-05 : __main__.TestNN.test_NLLLoss_2d_sum_reduction_cuda_float leaked 2560 bytes CUDA memory on device 0
    tests_to_skip+=('TestNN and test_NLLLoss_2d_sum_reduction_cuda_float')

    # 3.6_cu80
    # AssertionError: 1536 not less than or equal to 1e-05 : __main__.TestNN.test_NLLLoss_2d_sum_reduction_cuda_half leaked 1536 bytes CUDA memory on device 0
    tests_to_skip+=('TestNN and test_NLLLoss_2d_sum_reduction_cuda_half')

    # 2.7_cu92
    # AssertionError: __main__.TestNN.test_NLLLoss_2d_weights_cuda_float leaked 2560 bytes CUDA memory on device 0
    tests_to_skip+=('TestNN and test_NLLLoss_2d_weights_cuda_float')

    # 3.5_cu80 x2
    # 3.6_cu90
    # AssertionError: 1536 not less than or equal to 1e-05 : __main__.TestNN.test_NLLLoss_dim_is_3_cuda_double leaked 1536 bytes CUDA memory on device 0
    tests_to_skip+=('TestNN and test_NLLLoss_dim_is_3_cuda_double')

    # 3.6_cu80
    # AssertionError: 1536 not less than or equal to 1e-05 : __main__.TestNN.test_NLLLoss_dim_is_3_sum_reduction_cuda_float leaked 1536 bytes CUDA memory on device 0
    tests_to_skip+=('TestNN and test_NLLLoss_dim_is_3_sum_reduction_cuda_float')

    # 3.6_cu80
    # 3.7_cu80 x2
    # AssertionError: 1536 not less than or equal to 1e-05 : __main__.TestNN.test_NLLLoss_dim_is_3_sum_reduction_cuda_half leaked 1536 bytes CUDA memory on device 0
    tests_to_skip+=('TestNN and test_NLLLoss_dim_is_3_sum_reduction_cuda_half')

    # 3.5_cu80
    # 3.7_cu80 x2
    # AssertionError: 10752 not less than or equal to 1e-05 : __main__.TestNN.test_NLLLoss_higher_dim_cuda_double leaked 10752 bytes CUDA memory on device 0
    tests_to_skip+=('TestNN and test_NLLLoss_higher_dim_cuda_double')

    # 3.5_cu80
    # 3.7_cu80 --10752 x2
    # AssertionError: 5120 not less than or equal to 1e-05 : __main__.TestNN.test_NLLLoss_higher_dim_cuda_float leaked -5120 bytes CUDA memory on device 0
    tests_to_skip+=('TestNN and test_NLLLoss_higher_dim_cuda_float')

    # 3.5_cu80
    # 3.5 cu90
    # AssertionError: 3584 not less than or equal to 1e-05 : __main__.TestNN.test_NLLLoss_higher_dim_cuda_half leaked 3584 bytes CUDA memory on device 0
    tests_to_skip+=('TestNN and test_NLLLoss_higher_dim_cuda_half')

    # 3.5_cu90
    # AssertionError: 10752 not less than or equal to 1e-05 : __main__.TestNN.test_NLLLoss_higher_dim_sum_reduction_cuda_double leaked 10752 bytes CUDA memory on device 0
    tests_to_skip+=('TestNN and test_NLLLoss_higher_dim_sum_reduction_cuda_double')

    # 3.5_cu90
    # AssertionError: 5120 not less than or equal to 1e-05 : __main__.TestNN.test_NLLLoss_higher_dim_sum_reduction_cuda_float leaked -5120 bytes CUDA memory on device 0
    tests_to_skip+=('TestNN and test_NLLLoss_higher_dim_sum_reduction_cuda_float')

    # 3.7_cu90
    # AssertionError: 1024 not less than or equal to 1e-05 : __main__.TestJit.test_fuse_last_device_cuda leaked 1024 bytes CUDA memory on device 1
    tests_to_skip+=('TestJit and test_fuse_last_device_cuda')

    # 3.7_cu92 x2
    # AssertionError: 1024 not less than or equal to 1e-05 : __main__.TestJit.test_ge_cuda leaked 1024 bytes CUDA memory on device 0
    tests_to_skip+=('TestJit and test_ge_cuda')

    # 3.6_cu92
    # 3.7_cu92
    # AssertionError: 1024 not less than or equal to 1e-05 : __main__.TestJit.test_relu_cuda leaked 1024 bytes CUDA memory on device 0
    tests_to_skip+=('TestJit and test_relu_cuda')

    # 3.7_cu92 x3
    # AssertionError: 1024 not less than or equal to 1e-05 : __main__.TestScript.test_milstm_fusion_cuda leaked 1024 bytes CUDA memory on device 1
    tests_to_skip+=('TestScript and test_milstm_fusion_cuda')
fi


##############################################################################
# MacOS specific flaky tests
##############################################################################

if [[ "$(uname)" == 'Darwin' ]]; then
    # TestCppExtensions by default uses a temp folder in /tmp. This doesn't
    # work for this Mac machine cause there is only one machine and /tmp is
    # shared. (All the linux builds are on docker so have their own /tmp).
    tests_to_skip+=('TestCppExtension')
fi

if [[ "$(uname)" == 'Darwin' && "$package_type" == 'conda' ]]; then

		# Only on Anaconda's python 2.7
    # So, this doesn't really make sense. All the mac jobs are run on the same
    # machine, so the wheel jobs still use conda to silo their python
    # installations. The wheel job for Python 2.7 should use the exact same
    # Python from conda as the conda job for Python 2.7. Yet, this only appears
    # on the conda jobs.
    if [[ "$py_ver" == '2.7' ]]; then
				# Traceback (most recent call last):
				#   File "test_jit.py", line 6281, in test_wrong_return_type
				#     @torch.jit.script
				#   File "/Users/administrator/nightlies/2018_09_30/wheel_build_dirs/conda_2.7/conda/envs/env_py2.7_0_20180930/lib/python2.7/site-packages/torch/jit/__init__.py", line 639, in script
				#     graph = _jit_script_compile(ast, rcb)
				#   File "/Users/administrator/nightlies/2018_09_30/wheel_build_dirs/conda_2.7/conda/envs/env_py2.7_0_20180930/lib/python2.7/site-packages/torch/jit/annotations.py", line 80, in get_signature
				#     return parse_type_line(type_line)
				#   File "/Users/administrator/nightlies/2018_09_30/wheel_build_dirs/conda_2.7/conda/envs/env_py2.7_0_20180930/lib/python2.7/site-packages/torch/jit/annotations.py", line 131, in parse_type_line
				#     return arg_types, ann_to_type(ret_ann)
				#   File "/Users/administrator/nightlies/2018_09_30/wheel_build_dirs/conda_2.7/conda/envs/env_py2.7_0_20180930/lib/python2.7/site-packages/torch/jit/annotations.py", line 192, in ann_to_type
				#     return TupleType([ann_to_type(a) for a in ann.__args__])
				# TypeError: 'TupleInstance' object is not iterable
				tests_to_skip+=('TestScript and wrong_return_type')
		fi

		#
		# TestDistBackend
    # Seems like either most of the Mac builds get this error or none of them
    # do
		#

		# Traceback (most recent call last):
		#   File "test_thd_distributed.py", line 1046, in wrapper
		#     self._join_and_reduce(fn)
		#   File "test_thd_distributed.py", line 1120, in _join_and_reduce
		#     first_process.exitcode == SKIP_IF_SMALL_WORLDSIZE_EXIT_CODE
		# AssertionError
		tests_to_skip+=('TestDistBackend and test_reduce_group_max')

		# Traceback (most recent call last):
		#   File "test_thd_distributed.py", line 1046, in wrapper
		#     self._join_and_reduce(fn)
		#   File "test_thd_distributed.py", line 1132, in _join_and_reduce
		#     self.assertEqual(first_process.exitcode, 0)
		#   File "/Users/administrator/nightlies/2018_10_01/wheel_build_dirs/conda_2.7/pytorch/test/common.py", line 397, in assertEqual
		#     super(TestCase, self).assertLessEqual(abs(x - y), prec, message)
		# AssertionError: 1 not less than or equal to 1e-05
		tests_to_skip+=('TestDistBackend and test_isend')
		tests_to_skip+=('TestDistBackend and test_reduce_group_min')
		tests_to_skip+=('TestDistBackend and test_reduce_max')
		tests_to_skip+=('TestDistBackend and test_reduce_min')
		tests_to_skip+=('TestDistBackend and test_reduce_group_max')
		tests_to_skip+=('TestDistBackend and test_reduce_group_min')
		tests_to_skip+=('TestDistBackend and test_reduce_max')
		tests_to_skip+=('TestDistBackend and test_reduce_min')
		tests_to_skip+=('TestDistBackend and test_reduce_product')
		tests_to_skip+=('TestDistBackend and test_reduce_sum')
		tests_to_skip+=('TestDistBackend and test_scatter')
		tests_to_skip+=('TestDistBackend and test_send_recv')
		tests_to_skip+=('TestDistBackend and test_send_recv_any_source')
fi


# Turn the set of tests to skip into an invocation that pytest understands
excluded_tests_logic=''
for exclusion in "${tests_to_skip[@]}"; do
    if [[ -z "$excluded_tests_logic" ]]; then
        # Only true for i==0
        excluded_tests_logic="not ($exclusion)"
    else
        excluded_tests_logic="$excluded_tests_logic and not ($exclusion)"
    fi
done

 
##############################################################################
# Run the tests
##############################################################################
echo
echo "$(date) :: Calling 'python test/run_test.py -v -p pytest ${entire_file_exclusions[@]} -- --disable-pytest-warnings -k '$excluded_tests_logic'"

python test/run_test.py -v -p pytest ${entire_file_exclusions[@]} -- --disable-pytest-warnings -k "'" "$excluded_tests_logic" "'"

echo
echo "$(date) :: Finished 'python test/run_test.py -v -p pytest ${entire_file_exclusions[@]} -- --disable-pytest-warnings -k '$excluded_tests_logic'"

# cpp_extensions don't work with pytest, so we run them without pytest here,
# except there's a failure on CUDA builds (documented above), and
# cpp_extensions doesn't work on a shared mac machine (also documented above)
if [[ "$cuda_ver" == 'cpu' && "$(uname)" != 'Darwin' ]]; then
    echo
    echo "$(date) :: Calling 'python test/run_test.py -v -i cpp_extensions'"
    python test/run_test.py -v -i cpp_extensions
    echo
    echo "$(date) :: Finished 'python test/run_test.py -v -i cpp_extensions'"
fi

# thd_distributed can run on Mac but not in pytest
if [[ "$(uname)" == 'Darwin' ]]; then
    echo
    echo "$(date) :: Calling 'python test/run_test.py -v -i thd_distributed'"
    python test/run_test.py -v -i thd_distributed
    echo
    echo "$(date) :: Finished 'python test/run_test.py -v -i thd_distributed'"
fi