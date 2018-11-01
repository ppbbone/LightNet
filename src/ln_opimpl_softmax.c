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
     tl_tensor *dst;
     char      *dst_name;
     int        axis;
};

/*
 * This function should do the parameter checking and tensor shape inference.
 */
static void softmax_pre_run(ln_op_arg *op_arg, ln_error **error)
{
     char *src_name, *dst_name;
     ln_tensor_entry *src_entry, *dst_entry;
     tl_tensor *dst_tensor;
     ln_param_entry *axis_entry;
     int axis;
     int tensors_n, params_n;
     struct priv_s *priv;

     /* check tensors and parameters */
     tensors_n = ln_tensor_list_length(op_arg->tensors_in);
     ln_opck_tensor_in_len_eq(tensors_n, 1);

     tensors_n = ln_tensor_list_length(op_arg->tensors_out);
     ln_opck_tensor_in_len_eq(tensors_n, 1);

     src_name = ln_tensor_list_find_name(op_arg->tensors_in, "src");
     ln_opck_tensor_in_exist(src_name, "src");
     src_entry = ln_tensor_table_find(op_arg->tensor_table, src_name);
     ln_opck_tensor_defined(src_entry, src_name);
     ln_opck_tensor_mtype_eq(src_entry, LN_MEM_CPU);

     dst_name = ln_tensor_list_find_name(op_arg->tensors_out, "dst");
     ln_opck_tensor_out_exist(dst_name, "dst");
     dst_entry = ln_tensor_table_find(op_arg->tensor_table, dst_name);
     ln_opck_tensor_not_defined(dst_entry, dst_name);

     params_n = ln_param_list_length(op_arg->params);
     ln_opck_param_len_eq(params_n, 1);

     axis_entry = ln_param_list_find(op_arg->params, "axis");
     ln_opck_param_exist(axis_entry, "axis");
     ln_opck_param_type(axis_entry, LN_PARAM_NUMBER);
     axis = axis_entry->value_int;
     ln_opck_param_satisfy_msg(axis == -1 || (axis >= 0 && axis < src_entry->tensor->dims[src_entry->tensor->ndim-1]), "\"axis\" should be -1 or match the dimisions of \"src\"");

     /* define output tensor shape, tensor data should be NULL */
     dst_tensor = tl_tensor_create(NULL, src_entry->tensor->ndim,
                                   src_entry->tensor->dims,
                                   src_entry->tensor->dtype);
     dst_entry = ln_tensor_entry_create(dst_name, dst_tensor);
     dst_entry->mtype = LN_MEM_CPU;
     ln_tensor_table_insert(op_arg->tensor_table, dst_name, dst_entry);

     /* use op_arg->priv to store private data to be used in other functions */
     priv = ln_alloc(sizeof(struct priv_s));
     priv->axis = axis;
     priv->dst = dst_tensor;
     priv->dst_name = dst_name;
     priv->src = src_entry->tensor;
     op_arg->priv = priv;
}

/*
 * This function should only do the calculations.
 */
static void softmax_run(ln_op_arg *op_arg, ln_error **error)
{
     /* TODO: add softmax_run */
}

/*
 * This function should free all the memory allocated by other *_run()s.
 */
static void softmax_post_run(ln_op_arg *op_arg, ln_error **error)
{
     struct priv_s *priv;

     priv = op_arg->priv;
     ln_tensor_table_remove(op_arg->tensor_table, priv->dst_name);
     ln_free(op_arg->priv);
}

/* specify other ln_op_arg fields */
static ln_op_arg op_arg_softmax = {
     .optype = "softmax",
};

/* struct used for op registration in ln_oplist.c */
ln_op ln_opimpl_softmax = {
     .op_arg = &op_arg_softmax,
     .pre_run = softmax_pre_run,
     .static_run = NULL,
     .run = softmax_run,
     .post_run = softmax_post_run
};