#! /usr/bin/env perl

use 5.014;
use warnings;
use strict;
use JSON;
use File::Copy;
use Cwd 'abs_path';
use Getopt::Long;
no warnings 'experimental::smartmatch';

my $usage = <<EOF;
Usage: $0 [OPTION] [JSON_FILE(s)]
Generate operator defination code from operator description JSON.
Read the JSON string from standard if JSON_FILE(s) are not given.
Print the output code to stdout if --dir and --root are omited.

options:
  -h, --help               print this message
  -d, --dir=<directory>    save operator defination file(s) in <directory>
  -r, --root=<root>        set project root directory; set to current directory
                           if <root> is omited; this option will save operator
                           defination file(s) in <root>/src, and add operator
                           declarations and such to <root>/src/ln_arch_*.c
EOF

my $root = '';
my $dir = '';
my $help = '';
GetOptions(
           'help' => \$help,
           'dir=s' => \$dir,
           'root:s' => sub {$root = $_[1] ? abs_path($_[1]) : abs_path('.')},
          ) or &exit_msg(1, $usage);
&exit_msg(0, $usage) if $help;

my @json_files = @ARGV;
if (@json_files == 0) {
    my $json_text = join '', <STDIN>;
    &parse_and_generate($json_text);
} else {
    foreach my $json_file (@json_files) {
        open JSON_FILE, '<', $json_file or die "Cannot open $json_file: $!";
        my $json_text = join '', <JSON_FILE>;
        close JSON_FILE;
        &parse_and_generate($json_text);
    }
}

sub parse_and_generate {
    my $json_text = shift;
    my $json = decode_json($json_text);
    if (exists $json->{ops}) {
        foreach my $op (@{$json->{ops}}) {
            &gen_code($op);
        }
    }
    if (exists $json->{optype}) {
        &gen_code($json);
    }
}

sub gen_code {
    my $op = shift;
    &err_exit("needs a `optype`") unless exists $op->{optype};
    my $optype = $op->{optype};
    &err_exit("'${optype}' needs a `tensors_in`") unless exists $op->{tensors_in};
    my $tensors_in = $op->{tensors_in};
    &err_exit("'${optype}' needs a `tensors_out`") unless exists $op->{tensors_out};
    my $tensors_out = $op->{tensors_out};
    &err_exit("'${optype}' needs a `params`") unless exists $op->{params};
    my $params = $op->{params};

    my $subfix = "";
    $subfix = $op->{subfix} if exists $op->{subfix};
    if ($subfix && not $optype =~ /\w+_$subfix/) {
        &err_exit("'${optype}' doesn't match `subfix` '${subfix}'");
    }
    if ($subfix && $subfix ne "cuda") {
        &err_exit("'${optype}' has unsupported `subfix` '${subfix}'");
    }
    if (not $subfix) {
        $subfix = "cpu";
    }

    my @blocks = ();
    push @blocks, &gen_head_block($op);
    push @blocks, &gen_struct_def($op);
    push @blocks, &gen_pre_run($op);
    push @blocks, &gen_static_run($op) if exists $op->{static_run};
    push @blocks, &gen_run($op) if exists $op->{run};
    push @blocks, &gen_post_run($op);
    push @blocks, &gen_op_arg($op);
    push @blocks, &gen_op_impl($op);

    my $code_str = join "\n", @blocks;
    if (not $dir && not $root) {
        print $code_str;
    }
    if ($dir) {
        my $dir_file = "${dir}/ln_opimpl_${optype}.c";
        &backup_write($dir_file, $code_str);
    }
    if ($root) {
        my $src_file = "${root}/src/ln_opimpl_${optype}.c";
        &backup_write($src_file, $code_str);
        my $arch_file = "";
        if ($subfix eq "cpu") {
            $arch_file = "${root}/src/ln_arch_cpu.c";
        } elsif ($subfix eq "cuda") {
            $arch_file = "${root}/src/ln_arch_cuda.c";
        }
        &add_to_arch_file($arch_file, $optype, $subfix);
    }
}

sub backup_write {
    my $file = shift;
    my $str = shift;
    if (-e $file) {
        &warn_msg("${file} exists, backuped as ${file}.bak");
        copy($file, "${file}.bak")
            or die "Cannot backup file ${file}.bak: $!";
    }
    open FILE, '>', $file or die "Cannot open $file: $!";
    print FILE $str;
    close FILE;
}

sub add_to_arch_file {
    my $arch_file = shift;
    my $optype = shift;
    my $subfix = shift;

    my $declare = "extern ln_op ln_opimpl_${optype};";
    my $item = "&ln_opimpl_${optype},";

    copy($arch_file, "${arch_file}.bak")
        or die "Cannot backup file ${arch_file}: $!";
    open ARCH_FILE_BAK, '<', "${arch_file}.bak"
        or die "Cannot open ${arch_file}.bak: $!";
    open ARCH_FILE, '>', $arch_file
        or die "Cannot open ${arch_file}: $!";

    while (<ARCH_FILE_BAK>) {
        s|/\* end of declare $subfix ops \*/|$declare\n/* end of declare $subfix ops */|;
        s|/\* end of init $subfix ops \*/|     $item\n/* end of init $subfix ops */|;
        print ARCH_FILE;
    }

    close ARCH_FILE;
    close ARCH_FILE_BAK;
}

sub gen_head_block {
    my $head_block_tpl = <<EOF;
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
EOF
}

sub gen_struct_def {
    my $op = $_[0];
    my $tensors_in = $op->{tensors_in};
    my $tensors_out = $op->{tensors_out};
    my $params = $op->{params};

    my @defs = ();
    foreach (@$tensors_in) {
        &err_exit("'$op->{optype}' needs a `arg_name` in one of the  `tensors_in`") unless exists $_->{arg_name};
        push @defs, "tl_tensor *$_->{arg_name};";
    }
    foreach (@$tensors_out) {
        &err_exit("'$op->{optype}' needs a `arg_name` in one of the `tensors_out`") unless exists $_->{arg_name};
        push @defs, "tl_tensor *$_->{arg_name};";
        push @defs, "char *$_->{arg_name}_name;";
    }
    &gen_params($op, \@defs);
    &make_defs_neat(5, \@defs);

    my $defs_str = join "\n", @defs;
    my $struct_def_tpl = <<EOF;
struct priv_s {
${defs_str}
};
EOF
}

sub gen_pre_run {
    my $op = $_[0];
    my $pre_run_local_vars = &gen_pre_run_local_vars($op);
    my $pre_run_checks = &gen_pre_run_checks($op);
    my $output_tensor_def = &gen_output_tensor_def($op);
    my $priv_assigns = &gen_priv_assigns($op);

    my $pre_run_str = <<EOF;
/* This function should do the parameter checking and tensor shape inference. */
static void $op->{optype}_pre_run(ln_op_arg *op_arg, ln_error **error)
{
${pre_run_local_vars}
     /* check tensors and parameters */
${pre_run_checks}
     /* define output tensor shape, tensor data should be NULL */
${output_tensor_def}
     /* use op_arg->priv to store private data to be used in other functions */
${priv_assigns}
}
EOF
}

sub gen_pre_run_local_vars {
    my $op = $_[0];
    my $tensors_in = $op->{tensors_in};
    my $tensors_out = $op->{tensors_out};
    my $params = $op->{params};

    my @vars = ();
    foreach (@$tensors_in) {
        push @vars, "char *$_->{arg_name}_name;";
        push @vars, "ln_tensor_entry *$_->{arg_name}_entry;";
        push @vars, "tl_tensor *$_->{arg_name};";
    }
    foreach (@$tensors_out) {
        push @vars, "char *$_->{arg_name}_name;";
        push @vars, "ln_tensor_entry *$_->{arg_name}_entry;";
        push @vars, "tl_tensor *$_->{arg_name};";
        push @vars, "int $_->{arg_name}_ndim;";
        push @vars, "int *$_->{arg_name}_dims;";
        push @vars, "tl_dtype $_->{arg_name}_dtype;";
    }
    &gen_params($op, \@vars);

    push @vars, "int tensors_in_n;";
    push @vars, "int tensors_out_n;";
    push @vars, "int params_n;";
    push @vars, "struct priv_s *priv;";
    &make_defs_neat(5, \@vars);
    push @vars, "";

    join "\n", @vars;
}

sub gen_params {
    my $op = shift;
    my $params = $op->{params};
    my $defs = shift;
    foreach my $param (@$params) {
        &err_exit("'$op->{optype}' needs a `arg_name` in one of the `params`") unless exists $param->{arg_name};
        &err_exit("'$param->{arg_name}' needs a `ptype`") unless exists $param->{ptype};
        my $realtype;
        given ($param->{ptype}) {
            when ("LN_PARAM_NULL") {
                $realtype = "void *";
            }
            when ("LN_PARAM_STRING") {
                if (exists $param->{realtype}) {
                    $realtype = $param->{realtype};
                } else {
                    $realtype = "char *";
                }
            }
            when ("LN_PARAM_NUMBER") {
                &err_exit("$param->{arg_name} needs a `realtype`") unless exists $param->{realtype};
                if ($param->{realtype} eq "float" ||
                    $param->{realtype} eq "double"||
                    $param->{realtype} eq "int") {
                    $realtype = $param->{realtype};
                } else {
                    &err_exit("unsupported `realtype`: '$param->{realtype}'");
                }
            }
            when ("LN_PARAM_BOOL") {
                $realtype = "tl_bool_t";
            }
            when ("LN_PARAM_ARRAY_STRING") {
                if (exists $param->{realtype}) {
                    $realtype = "$param->{realtype} *";
                } else {
                    $realtype = "char **";
                }
            }
            when ("LN_PARAM_ARRAY_NUMBER") {
                &err_exit("$param->{arg_name} needs a `realtype`") unless exists $param->{realtype};
                if ($param->{realtype} eq "float" ||
                    $param->{realtype} eq "double"||
                    $param->{realtype} eq "int") {
                    $realtype = "$param->{realtype} *";
                } else {
                    &err_exit("$param->{arg_name} has unsupported `realtype`: '$param->{realtype}'");
                }
            }
            when ("LN_PARAM_ARRAY_BOOL") {
                $realtype = "tl_bool_t *";
            }
            default {
                &err_exit("$param->{arg_name} has unsupported `ptype`: '$param->{ptype}'");
            }
        }
        $realtype .= " " unless ($realtype =~ /\*$/);

        push @$defs, "${realtype}$param->{arg_name};";
    }
}

sub gen_pre_run_checks {
    my $op = $_[0];
    my $tensors_in = $op->{tensors_in};
    my $tensors_out = $op->{tensors_out};
    my $params = $op->{params};

    my @states = ();
    my $tensors_in_n = @$tensors_in;
    push @states, "tensors_in_n = ln_tensor_list_length(op_arg->tensors_in);";
    push @states, "ln_opck_tensor_in_len_eq(tensors_in_n, ${tensors_in_n});";
    push @states, "";
    foreach my $tensor (@$tensors_in) {
        my $arg_name = $tensor->{arg_name};
        push @states, "${arg_name}_name = ln_tensor_list_find_name(op_arg->tensors_in, \"${arg_name}\");";
        push @states, "ln_opck_tensor_in_exist(${arg_name}_name, \"${arg_name}\");";
        push @states, "${arg_name}_entry = ln_tensor_table_find(op_arg->tensor_table, ${arg_name}_name);";
        push @states, "ln_opck_tensor_defined(${arg_name}_entry, ${arg_name}_name);";
        &err_exit("'$tensor->{arg_name}' needs a `mtype`") unless exists $tensor->{mtype};
        push @states, "ln_opck_tensor_mtype_eq(${arg_name}_entry, $tensor->{mtype});";
        if (exists $tensor->{dtype}) {
            push @states, "ln_opck_tensor_dtype_eq(${arg_name}_entry, $tensor->{dtype});";
        }
        if (exists $tensor->{sametype}) {
            push @states, "ln_opck_tensor_issametype(${arg_name}_entry, $tensor->{sametype}_entry);";
        }
        if (exists $tensor->{sameshape}) {
            push @states, "ln_opck_tensor_issameshape(${arg_name}_entry, $tensor->{sametype}_entry);";
        }
        if (exists $tensor->{static}) {
            if ($tensor->{static}) {
                push @states, "ln_opck_tensor_isstatic(${arg_name}_entry);";
            } else {
                push @states, "ln_opck_tensor_isnotstatic(${arg_name}_entry);";
            }
        }
        if (exists $tensor->{check}) {
            push @states, "ln_opck_tensor_satisfy_msg($tensor->{check});";
        }
        if (exists $tensor->{checks}) {
            my $checks = $tensor->{checks};
            foreach (@$checks) {
                if (exists $_->{check}) {
                    push @states, "ln_opck_tensor_satisfy_msg($_->{check});";
                } else {
                    &err_exit("tensor '${arg_name}' expects a `check` in `checks`");
                }
            }
        }
        if (exists $tensor->{custom}) {
            &add_custom_block($tensor->{custom}, \@states);
        }
        push @states, "";
    }

    my $tensors_out_n = @$tensors_out;
    push @states, "tensors_out_n = ln_tensor_list_length(op_arg->tensors_out);";
    push @states, "ln_opck_tensor_out_len_eq(tensors_out_n, ${tensors_out_n});";
    push @states, "";
    foreach my $tensor (@$tensors_out) {
        my $arg_name = $tensor->{arg_name};
        push @states, "${arg_name}_name = ln_tensor_list_find_name(op_arg->tensors_out, \"${arg_name}\");";
        push @states, "ln_opck_tensor_in_exist(${arg_name}_name, \"${arg_name}\");";
        push @states, "${arg_name}_entry = ln_tensor_table_find(op_arg->tensor_table, ${arg_name}_name);";
        push @states, "ln_opck_tensor_not_defined(${arg_name}_entry, ${arg_name}_name);";
        push @states, "";
    }

    my $params_n = @$params;
    push @states, "params_n = ln_param_list_length(op_arg->params);";
    push @states, "ln_opck_param_len_eq(params_n, ${params_n});";
    push @states, "";
    foreach my $param (@$params) {
        my $arg_name = $param->{arg_name};
        push @states, "${arg_name}_entry = ln_param_list_find(op_arg->params, \"${arg_name}\");";
        push @states, "ln_opck_param_exist(${arg_name}_entry, \"${arg_name}\");";
        push @states, "ln_opck_param_type(${arg_name}_entry, $param->{ptype});";
        given ($param->{ptype}) {
            when ("LN_PARAM_NULL") {
                push @states, "${arg_name} = NULL;";
            }
            when ("LN_PARAM_STRING") {
                if (exists $param->{realtype}) {
                    if (exists $param->{from_func}) {
                        push @states, "${arg_name} = $param->{from_func}(${arg_name}_entry->value_string);";
                    } else {
                        &err_exit("$param->{arg_name} needs a `from_func` to convert '${arg_name}'");
                    }
                } else {
                    push @states, "${arg_name} = ${arg_name}_entry->value_string;";
                }
            }
            when ("LN_PARAM_NUMBER") {
                if ($param->{realtype} eq "float" ||
                    $param->{realtype} eq "double"||
                    $param->{realtype} eq "int") {
                    push @states, "${arg_name} = ${arg_name}_entry->value_$param->{realtype};";
                } else {
                    &err_exit("$param->{arg_name} has unsupported `realtype`: '$param->{realtype}'");
                }
            }
            when ("LN_PARAM_BOOL") {
                push @states, "${arg_name} = ${arg_name}_entry->value_bool;";
            }
            when (/^LN_PARAM_ARRAY/) {
                if (exists $param->{len}) {
                    push @states, "ln_opck_param_array_len_eq(${arg_name}_entry, $param->{len});";
                }
                continue ;
            }
            when ("LN_PARAM_ARRAY_STRING") {
              if (exists $param->{realtype}) {
                if (exists $param->{from_func}) {
                  push @states, "${arg_name} = ln_alloc(sizeof($param->{realtype})*${arg_name}_entry->array_len);";
                  push @states, "for (int i = 0; i < ${arg_name}_entry->array_len; i++)";
                  push @states, &indent_line(5, "${arg_name}[i] = $param->{from_func}(${arg_name}_entry->value_array_string[i]);");
                } else {
                  &err_exit("$param->{arg_name} needs a `from_func` to convert '${arg_name}'");
                }
              } else {
                push @states, "${arg_name} = ${arg_name}_entry->value_array_string;";
              }
            }
            when ("LN_PARAM_ARRAY_NUMBER") {
              if ($param->{realtype} eq "float" ||
                  $param->{realtype} eq "double"||
                  $param->{realtype} eq "int") {
                push @states, "${arg_name} = ${arg_name}_entry->value_array_$param->{realtype};";
              } else {
                &err_exit("$param->{arg_name} has unsupported `realtype`: '$param->{realtype}'");
              }
            }
            when ("LN_PARAM_ARRAY_BOOL") {
              push @states, "${arg_name} = ${arg_name}_entry->value_array_bool;";
            }
            default {
                &err_exit("$param->{arg_name} has unsupported `ptype`: '$param->{ptype}'");
            }
        }
        if (exists $param->{check}) {
            push @states, "ln_opck_param_satisfy_msg($param->{check});";
        }
        if (exists $param->{checks}) {
            my $checks = $param->{checks};
            foreach (@$checks) {
                if (exists $_->{check}) {
                    push @states, "ln_opck_param_satisfy_msg($_->{check});";
                } else {
                    &err_exit("$param->{arg_name} expects a `check` in `checks`");
                }
            }
        }
        if (exists $param->{custom}) {
            &add_custom_block($param->{custom}, \@states);
        }
        push @states, "";
    }

    if (exists $op->{extra_checks}) {
        my $checks = $op->{extra_checks};
        foreach (@$checks) {
            if (exists $_->{cktype} && exists $_->{check}) {
                if ($_->{cktype} ne "param" && $_->{cktype} ne "tensor") {
                    &err_exit("`extra_checks`'s `cktype` should be 'param' or 'tensor'");
                }
                push @states, "ln_opck_$_->{cktype}_satisfy_msg($_->{check});";
            } else {
                &err_exit("`extra_checks` expects a `cktype` and a `check`");
            }
        }
        push @states, "";
    }
    if (exists $op->{extra_custom}) {
        &add_custom_block($op->{extra_custom}, \@states);
        push @states, "";
    }

    &indent_block(5, \@states);
    join "\n", @states;
}

sub gen_output_tensor_def {
    my $op = $_[0];
    my $tensors_out = $op->{tensors_out};

    my @states = ();
    foreach my $tensor (@$tensors_out) {
        my $arg_name = $tensor->{arg_name};
        if (exists $tensor->{ndim}) {
            push @states, "${arg_name}_ndim = $tensor->{ndim};";
        } elsif (not exists $tensor->{custom}) {
            &err_exit("'${arg_name}' needs a `ndim` or `custom` to give the defination of ${arg_name}_ndim");
        }
        if (exists $tensor->{dims}) {
            push @states, "${arg_name}_dims = $tensor->{dims};";
        } elsif (not exists $tensor->{custom}) {
            &err_exit("'${arg_name}' needs a `dims` or `custom` to give the defination of ${arg_name}_dims");
        }
        if (exists $tensor->{dtype}) {
            push @states, "${arg_name}_dtype = $tensor->{dtype};";
        } elsif (not exists $tensor->{custom}) {
            &err_exit("'${arg_name}' needs a `dtype` or `custom` to give the defination of ${arg_name}_dtype");
        }
        if (exists $tensor->{custom}) {
            &add_custom_block($tensor->{custom}, \@states);
        }
        push @states, "${arg_name} = tl_tensor_create(NULL, ${arg_name}_ndim, ${arg_name}_dims, ${arg_name}_dtype);";
        push @states, "${arg_name}_entry = ln_tensor_entry_create(${arg_name}_name, ${arg_name});";
        if (exists $tensor->{mtype}) {
            push @states, "${arg_name}_entry->mtype = $tensor->{mtype};";
        } else {
            &err_exit("${arg_name} needs a `mtype`");
        }
        push @states, "ln_tensor_table_insert(op_arg->tensor_table, ${arg_name}_name, ${arg_name}_entry);";
        if (exists $tensor->{cleanup}) {
            &add_custom_block($tensor->{cleanup}, \@states);
        }
        push @states, "";
    }

    &indent_block(5, \@states);
    join "\n", @states;
}

sub gen_priv_assigns {
    my $op = $_[0];
    my $tensors_in = $op->{tensors_in};
    my $tensors_out = $op->{tensors_out};
    my $params = $op->{params};

    my @states = ();
    push @states, "priv = ln_alloc(sizeof(struct priv_s));";
    foreach (@$tensors_in) {
        push @states, "priv->$_->{arg_name} = $_->{arg_name};";
    }
    foreach (@$tensors_out) {
        push @states, "priv->$_->{arg_name} = $_->{arg_name};";
        push @states, "priv->$_->{arg_name}_name = $_->{arg_name}_name;";
    }
    foreach (@$params) {
        push @states, "priv->$_->{arg_name} = $_->{arg_name};";
    }
    push @states, "op_arg->priv = priv;";

    &indent_block(5, \@states);
    join "\n", @states;
}

sub gen_static_run {
    my $op = $_[0];

    my @states = ();
    push @states, "struct priv_s *priv = op_arg->priv;";
    push @states, "";
    &add_custom_block($op->{static_run}, \@states);
    &indent_block(5, \@states);
    my $states_str = join "\n", @states;

    my $static_run_tpl = <<EOF;
/* This function blocks only once per instance right after memory allocation. */
static void $op->{optype}_static_run(ln_op_arg *op_arg, ln_error **error)
{
${states_str}
}
EOF
}

sub gen_run {
    my $op = $_[0];

    my @states = ();
    push @states, "struct priv_s *priv = op_arg->priv;";
    push @states, "";
    &add_custom_block($op->{run}, \@states);
    &indent_block(5, \@states);
    my $states_str = join "\n", @states;

    my $static_run_tpl = <<EOF;
/* This function should only do the calculations. */
static void $op->{optype}_run(ln_op_arg *op_arg, ln_error **error)
{
${states_str}
}
EOF
}

sub gen_post_run {
    my $op = $_[0];
    my $tensors_out = $op->{tensors_out};

    my @states = ();
    push @states, "struct priv_s *priv = op_arg->priv;";
    push @states, "";
    foreach (@$tensors_out) {
        push @states, "ln_tensor_table_remove(op_arg->tensor_table, priv->$_->{arg_name}_name);";
    }
    &add_custom_block($op->{post_run}, \@states);
    push @states, "ln_free(op_arg->priv);";

    &indent_block(5, \@states);
    my $states_str = join "\n", @states;

    my $static_run_tpl = <<EOF;
/* This function should free all the memory allocated by other *_run()s. */
static void create_post_run(ln_op_arg *op_arg, ln_error **error)
{
${states_str}
}
EOF
}

sub gen_op_arg {
    my $op = $_[0];

    my $op_arg_tpl = <<EOF;
/* specify other ln_op_arg fields */
static ln_op_arg op_arg_$op->{optype} = {
     .optype = "$op->{optype}",
};
EOF
}

sub gen_op_impl {
    my $op = $_[0];
    my $static_run_func = exists $op->{static_run} ? "$op->{optype}_static_run" : "NULL";
    my $run_func = exists $op->{run} ? "$op->{optype}_run" : "NULL";

    my $op_impl_tpl = <<EOF;
/* struct used for op registration in ln_oplist.c */
ln_op ln_opimpl_$op->{optype} = {
     .op_arg = &op_arg_$op->{optype},
     .pre_run = $op->{optype}_pre_run,
     .static_run = ${static_run_func},
     .run = ${run_func},
     .post_run = $op->{optype}_post_run
};
EOF
}

sub add_custom_block {
    my $custom_str = shift;
    my $states = shift;
    my @customs = split "\n", $custom_str;
    &indent_block(5, \@customs);
    push @$states, "{";
    push @$states, @customs;
    push @$states, "}";
}

sub make_defs_neat {
    my $nspaces = shift;
    my $defs = shift;
    my $max_offset = 0;
    foreach (@$defs) {
        if (/( |\*)(\w+;)/) {
            my $offset = index($_, $2);
            $max_offset = $max_offset < $offset ? $offset : $max_offset;
        } else {
            &err_exit("make_defs_neat: wrong format: $_");
        }
    }
    foreach (@$defs) {
        my $type = $1 if /((\w+[ \t]+)+)/;
        $type =~ s/[ \t]+$//;
        my $nstars = 0;
        $nstars = length $1 if /(\*+)/;
        my $rest = $2 if /( |\*)(\w+;)/;
        $_ = sprintf("%-${max_offset}s", $type);
        my $re = " "x$nstars;
        my $stars = "*"x$nstars;
        s/$re$/$stars$rest/;
    }
    &indent_block($nspaces, $defs);
}

sub indent_block {
    my $nspaces = shift;
    my $states = shift;
    $_ = " "x$nspaces.$_ foreach @$states;
}

sub indent_line {
    my $nspaces = shift;
    my $state = shift;
    $state = " "x$nspaces.$state;
}

sub err_exit {
    my $msg = $_[0];
    print STDERR "ERROR: $msg\n";
    exit 1;
}

sub warn_msg {
    my $msg = $_[0];
    print STDERR "WARNING: $msg\n";
}

sub exit_msg {
    my $status = shift;
    my $msg = shift;
    print $msg;
    exit $status;
}