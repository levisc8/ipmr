## Rebuilds Compagnoni et al. 2016 Ecological Monographs IPM.

# library(ipmr)
devtools::load_all()
library(rlang)
library(purrr)
library(dplyr)

source('paper/Analyses/R/padr_helpers.R')

# read in data and subset to aldo's model

use_padr <- readRDS('paper/Analyses/Data/padrino_for_paper.rds')

# Split up tables and get to mapping the DB to ipmr format

dom_tab  <- use_padr[[2]]
int_tab  <- use_padr[[3]]
kern_tab <- use_padr[[4]]
vre_tab  <- use_padr[[5]]
par_tab  <- use_padr[[6]]
ref_tab  <- use_padr[[7]]


# Next, remove the parameters that are just assigning themselves
vre_tab <- vre_tab %>%
  mutate(param_assign = map_lgl(.x = .data$formula, ~is_the_same(.x))) %>%
  filter(!param_assign) %>%
  select(-param_assign)


dom_vec <- c(dom_tab$lower, dom_tab$upper, int_tab$n_meshpoints)

# Parse kernel formulae

p_form <- kern_tab$formula[grepl('P_', kern_tab$kernel_id)]

p_form <- rm_brackets(p_form) %>%
  unlist() %>%
  parse_expr()

b1_form <- kern_tab$formula[grepl('B1_', kern_tab$kernel_id)] %>%
  rm_brackets
f_expanded <- kern_tab$formula[grepl("F_yr", kern_tab$kernel_id)] %>%
  rm_brackets(.)

b1_form[[1]] <- gsub(names(f_expanded), f_expanded[[1]], b1_form[[1]])

b1_form <- b1_form %>% unlist() %>% parse_expr()

b2_form <- kern_tab$formula[kern_tab$kernel_id == 'B2_yr']

b2_form <- rm_brackets(b2_form)

b2_form <- gsub('\\* SB1_1', '', b2_form[[1]]) %>%
  parse_expr()

b1c_form <- kern_tab$formula[kern_tab$kernel_id == 'B1C_yr'] %>%
  gsub('SB1_1 \\* ', '', x = .) %>%
  rm_brackets() %>%
  unlist() %>%
  parse_expr()

b2c_form <- kern_tab$formula[kern_tab$kernel_id == 'B2C_yr'] %>%
  gsub('SB2_1 \\* ', '', x = .) %>%
  rm_brackets() %>%
  unlist() %>%
  parse_expr()

# parameter values
all_param_list <- lapply(par_tab$parameter_value,
                         function(x) x)
names(all_param_list) <- par_tab$parameter_name
all_param_list$g_sd <- 0.860752

# We're tantalizingly close - just need to modify vre_exprs

p_exprs <- vre_tab$formula[grepl('P_yr', vre_tab$kernel_id)]

p_exprs <- rm_brackets(p_exprs)
p_exprs$g_yr <- gsub(' Norm\\(', 'dnorm\\(lnsize_2, ', p_exprs$g_yr)
p_exprs <- lapply(p_exprs, parse_expr)

# Correct log to exp for link in seed regression
b1_exprs <- vre_tab$formula[grepl("F_yr|B1_yr", vre_tab$kernel_id)]
b1_exprs[2] <- gsub('log', 'exp', b1_exprs[2])
b1_exprs <- rm_brackets(b1_exprs) %>%
  lapply(parse_expr)

b2_exprs <- vre_tab$formula[grepl('F_yr|B2_yr', vre_tab$kernel_id)]
b2_exprs[2] <- gsub('log', 'exp', b2_exprs[2])
b2_exprs <- b2_exprs %>%
  rm_brackets() %>%
  lapply(parse_expr)

# This has a couple mistakes in it that need correcting

b1c_exprs <- vre_tab$formula[grepl('B1C_yr', vre_tab$kernel_id)]
b1c_exprs <- gsub('\\[', '\\(', b1c_exprs)
b1c_exprs <- gsub('\\]', '\\)', b1c_exprs)
b1c_exprs <- gsub('Norm\\(', 'dnorm\\(lnsize_2, ', b1c_exprs) %>%
  rm_brackets() %>%
  lapply(parse_expr)

b2c_exprs <- b1c_exprs

init_pop_vec <- list(
  lnsize = runif(200),
  b_1    = 10,
  b_2    = 10
)

full_mod <- init_ipm(use_padr[[1]]$model_class) %>%
  define_kernel(
    name = 'P_yr',
    formula = !! p_form,
    family = 'CC',
    !!! p_exprs,
    data_list = all_param_list,
    states = list(c('lnsize')),
    uses_par_sets = TRUE,
    par_set_indices = list2(
      !! ref_tab$vr_expr_name := eval_bare(
        parse_expr(ref_tab$range)
      )
    )
  ) %>%
  define_kernel(
    name = 'b1_yr',

    # need to modify this first, there is no CC transition for fecundity in this model

    formula = !! b1_form,
    family = 'CD',
    !!! b1_exprs,
    data_list = all_param_list,
    states = list(c('lnsize')),
    uses_par_sets = TRUE,
    par_set_indices = list2(
      !! ref_tab$vr_expr_name := eval_bare(
        parse_expr(ref_tab$range)
      )
    )
  ) %>%
  define_kernel(
    name = 'b2_yr',
    formula = !! b2_form,
    family = 'DD',
    !!! b2_exprs,
    data_list = all_param_list,
    states = list(c('lnsize')),
    uses_par_sets = TRUE,
    par_set_indices = list2(
      !! ref_tab$vr_expr_name := eval_bare(
        parse_expr(ref_tab$range)
      )
    )
  ) %>%
  define_kernel(
    name = 'leave_b2_yr',
    formula = !! b2c_form,
    family = 'Dc',
    !!! b2c_exprs,
    data_list = all_param_list,
    states = list(c('lnsize')),
    uses_par_sets = TRUE,
    par_set_indices = list2(
      !! ref_tab$vr_expr_name := eval_bare(
        parse_expr(ref_tab$range)
      )
    )
  ) %>%
  define_kernel(
    name = 'leave_b1_yr',
    formula = !! b1c_form,
    family = "DC",
    !!! b1c_exprs,
    data_list = all_param_list,
    states = list(c('lnsize')),
    uses_par_sets = TRUE,
    par_set_indices = list2(
      !! ref_tab$vr_expr_name := eval_bare(
        parse_expr(ref_tab$range)
      )
    )
  ) %>%
  define_k(
    name = 'K_yr',
    family = 'IPM',
    n_lnsize_t_1 = P_yr     %*% n_lnsize_t * d_lnsize +
      leave_b1_yr %*% n_b_1_t +
      leave_b2_yr %*% n_b_2_t,
    n_b_1_t_1 = b1_yr %*% n_lnsize_t * d_lnsize,
    n_b_2_t_1 = b2_yr %*% n_b_1_t,
    states = list(c('lnsize')),
    uses_par_sets = TRUE,
    par_set_indices = list(yr = 2004:2014)
  ) %>%
  define_impl(
    make_impl_args_list(
      kernel_names = c('P_yr', "b1_yr", 'b2_yr', 'leave_b2_yr', 'leave_b1_yr', 'K_yr'),
      int_rule = rep('midpoint', 6),
      dom_start = c('lnsize', 'lnsize', NA_character_,
                    NA_character_, NA_character_, NA_character_),
      dom_end = c('lnsize', NA_character_, NA_character_,
                  'lnsize', 'lnsize', NA_character_)
    )
  ) %>%
  define_domains(
    lnsize = dom_vec
  ) %>%
  define_pop_state(
    pop_vectors = list(
      n_lnsize = init_pop_vec$lnsize,
      n_b_1    = init_pop_vec$b_1,
      n_b_2    = init_pop_vec$b_2
    )
  ) %>%
  make_ipm(iterate = TRUE,
           iterations = 50,
           return_all = TRUE,
           report_progress = TRUE)
