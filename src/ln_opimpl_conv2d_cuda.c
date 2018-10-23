/*
 * Copyright (c) 2018 Zhao Zhixu
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

#include <assert.h>
#include "ln_op.h"

struct priv_s {
     tl_tensor *src;
     tl_tensor *weight;
     tl_tensor *dst;
     char      *dst_name;
     int       *size;
     int       *stride;
     int       *padding;
     int       *dilation;
     int        group;
};

static int compute_output_dim(int input_dim, int size, int stride, int padding)
{
     return ((input_dim + padding) - size) / stride + 1;
}

/*
 * This function should do the parameter checking and tensor shape inference.
 */
static void conv2d_cuda_pre_run(ln_op_arg *op_arg, ln_error **error)
{
     char *src_name, *weight_name, *dst_name;
     ln_tensor_entry *src_entry, *weight_entry, *dst_entry;
     ln_param_entry *group_entry, *size_entry, *stride_entry,
          *padding_entry, *dilation_entry;
     int tensors_n, params_n;
     tl_tensor *dst_tensor;
     int       *size;
     int       *stride;
     int       *padding;
     int       *dilation;
     int        group;
     struct priv_s *priv;

     /* check tensors and parameters */
     tensors_n = ln_tensor_list_length(op_arg->tensors_in);
     ln_op_check_tensor_in_len_eq(tensors_n, 2);

     tensors_n = ln_tensor_list_length(op_arg->tensors_out);
     ln_op_check_tensor_out_len_eq(tensors_n, 1);

     src_name = ln_tensor_list_find_name(op_arg->tensors_in, "src");
     ln_op_check_tensor_in_exist(src_name, "src");
     src_entry = ln_tensor_table_find(op_arg->tensor_table, src_name);
     ln_op_check_tensor_defined(src_entry, src_name);
     ln_op_check_tensor_satisfy_msg(src_entry->tensor->ndim == 4,
                                    "\"src\" should be a 4-dimensional tensor");

     weight_name = ln_tensor_list_find_name(op_arg->tensors_in, "weight");
     ln_op_check_tensor_in_exist(weight_name, "weight");
     weight_entry = ln_tensor_table_find(op_arg->tensor_table, weight_name);
     ln_op_check_tensor_defined(weight_entry, weight_name);
     ln_op_check_tensor_satisfy_msg(src_entry->tensor->ndim == 5,
                                    "\"weight\" should be a 5-dimensional tensor");

     dst_name = ln_tensor_list_find_name(op_arg->tensors_out, "dst");
     ln_op_check_tensor_out_exist(dst_name, "dst");
     dst_entry = ln_tensor_table_find(op_arg->tensor_table, dst_name);
     ln_op_check_tensor_not_defined(dst_entry, dst_name);

     params_n = ln_param_list_length(op_arg->params);
     ln_op_check_param_len_eq(params_n, 5);

     /* TODO: check the group */
     group_entry = ln_param_list_find(op_arg->params, "group");
     ln_op_check_param_exist(group_entry, "group");
     ln_op_check_param_type(group_entry, LN_PARAM_NUMBER);
     group = group_entry->value_int;
     ln_op_check_param_satisfy_msg(group == weight_entry->tensor->dims[0],
                                   "\"group\" should be equal to the first dimension of \"weight\"");

     size_entry = ln_param_list_find(op_arg->params, "size");
     ln_op_check_param_exist(size_entry, "size");
     ln_op_check_param_type(size_entry, LN_PARAM_ARRAY_NUMBER);
     ln_op_check_param_array_len_eq(size_entry, 2);
     size = size_entry->value_array_int;

     stride_entry = ln_param_list_find(op_arg->params, "stride");
     ln_op_check_param_exist(stride_entry, "stride");
     ln_op_check_param_type(stride_entry, LN_PARAM_ARRAY_NUMBER);
     ln_op_check_param_array_len_eq(stride_entry, 2);
     stride = stride_entry->value_array_int;

     padding_entry = ln_param_list_find(op_arg->params, "padding");
     ln_op_check_param_exist(padding_entry, "padding");
     ln_op_check_param_type(padding_entry, LN_PARAM_ARRAY_NUMBER);
     ln_op_check_param_array_len_eq(padding_entry, 4);
     padding = padding_entry->value_array_int;

     /* TODO: check this throughly */
     dilation_entry = ln_param_list_find(op_arg->params, "dilation");
     ln_op_check_param_exist(dilation_entry, "dilation");
     ln_op_check_param_type(dilation_entry, LN_PARAM_ARRAY_NUMBER);
     ln_op_check_param_array_len_eq(dilation_entry, 2);
     dilation = dilation_entry->value_array_int;

     ln_op_check_param_satisfy_msg(size[0] == weight_entry->tensor->dims[3] &&
                                   size[1] == weight_entry->tensor->dims[4],
                                   "\"size\" should match the last two dimensions of \"weight\"");

     /* define output tensor shape, tensor data should be NULL */
     int dims[4];
     dims[0] = src_entry->tensor->dims[0];
     dims[1] = weight_entry->tensor->dims[1];
     dims[2] = compute_output_dim(src_entry->tensor->dims[2], size[0],
                                  stride[0], padding[0] + padding[1]);
     dims[3] = compute_output_dim(src_entry->tensor->dims[3], size[1],
                                  stride[1], padding[2] + padding[3]);
     dst_tensor = tl_tensor_create(NULL, 4, dims, src_entry->tensor->dtype);
     dst_entry = ln_tensor_entry_create(dst_name, dst_tensor);
     ln_tensor_table_insert(op_arg->tensor_table, dst_name, dst_entry);

     /* use op_arg->priv to store private data to be used in other functions */
     priv = ln_alloc(sizeof(struct priv_s));
     priv->dilation = dilation;
     priv->dst = dst_tensor;
     priv->dst_name = dst_name;
     priv->group = group;
     priv->padding = padding;
     priv->size = size;
     priv->src = src_entry->tensor;
     priv->stride = stride;
     priv->weight = weight_entry->tensor;
     op_arg->priv = priv;
}

/*
 * This function should only do the calculations.
 */
static void conv2d_cuda_run(ln_op_arg *op_arg, ln_error **error)
{
     /* TODO: add conv2d_cuda_run */
}

/*
 * This function should undo everything done by pre_run().
 */
static void conv2d_cuda_post_run(ln_op_arg *op_arg, ln_error **error)
{
     struct priv_s *priv;

     priv = op_arg->priv;
     ln_tensor_table_remove(op_arg->tensor_table, priv->dst_name);
     ln_free(op_arg->priv);
}

/* specify other ln_op_arg fields */
static ln_op_arg op_arg_conv2d_cuda = {
     .optype = "conv2d_cuda",
     .mtype_in = LN_MEM_CUDA,
     .mtype_out = LN_MEM_CUDA,
};

/* struct used for op registration in ln_oplist.c */
ln_op ln_opimpl_conv2d_cuda = {
     .op_arg = &op_arg_conv2d_cuda,
     .pre_run = conv2d_cuda_pre_run,
     .static_run = NULL,
     .run = conv2d_cuda_run,
     .post_run = conv2d_cuda_post_run
};