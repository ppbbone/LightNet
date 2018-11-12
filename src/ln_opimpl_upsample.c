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

/*
 * This function should do the parameter checking and tensor shape inference.
 */
static void upsample_pre_run(ln_op_arg *op_arg, ln_error **error)
{

     /* check tensors and parameters */

     /* define output tensor shape, tensor data should be NULL */

     /* use op_arg->priv to store private data to be used in other functions */
}

/*
 * This function should only do the calculations.
 */
static void upsample_run(ln_op_arg *op_arg, ln_error **error)
{

}

/*
 * This function should free all the memory allocated by other *_run()s.
 */
static void upsample_post_run(ln_op_arg *op_arg, ln_error **error)
{

}

/* specify other ln_op_arg fields */
static ln_op_arg op_arg_upsample = {
     .optype = "upsample",
};

/* struct used for op registration in ln_oplist.c */
ln_op ln_opimpl_upsample = {
     .op_arg = &op_arg_upsample,
     .pre_run = upsample_pre_run,
     .static_run = NULL,
     .run = upsample_run,
     .post_run = upsample_post_run
};