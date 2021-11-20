##############################################
## The following are the functions to be used in a self-sim
## pipeline.
##############################################


# init + packages ---------------------------------------------------------

library(tidyverse)
# library(plyr)
library(MplusAutomation)
library(here)
library(primes)
rm(list = ls())

source(here::here("functions",
                  "functions_data-generating-models.R"))

# Make population ---------------------------------------------------------

make_population <- function(Model = "DAR",
                            T = 100,
                            N = 100,
                            phi = 0.4,
                            l2.distribution = "Gaussian",
                            seed = 0) {
  # save global seed of the global env and set it back before leaving
  seed.old <- .Random.seed
  on.exit({
    .Random.seed <<- seed.old
  })
  set.seed(seed)

  if (tolower(Model) == "chiar" | tolower(Model) == "chi2ar") {
    model.name <- "Chi2AR"
    lev2.Mean <- 10
    lev2.Variance <- 10
    chi2.df <- 5
  }
  if (tolower(Model) == "binar") {
    model.name <- "BinAR"
    lev2.Mean <- 2
    lev2.Variance <- 1
    chi2.df <- 2.9
  }
  if (tolower(Model) == "dar") {
    model.name <- "DAR"
    lev2.Mean <- 2
    lev2.Variance <- 1
    chi2.df <- 2.9
  }

  # sampling within-person mean from level 2 distribution
  if (l2.distribution == "Gaussian")
    Means <- rnorm(2 * N, lev2.Mean, sqrt(lev2.Variance))
  if (l2.distribution == "Chi2")
    Means <- rchisq(2 * N, chi2.df)

  # removing out-of-bounds means
  Means[Means < 0] <- NA
  Means[Means > 100] <- NA
  if (model.name == "BinAR" |
      model.name == "DAR")
    Means[Means > 10] <- NA

  # keeping N samples from the in-bound means
  Means <- Means %>% na.omit() %>% sample(N)


  sample_df <- dgm_make.population(
    Model = Model,
    Means = Means,
    T = T,
    phi = phi,
    seeds = NULL
  )
  return(sample_df)
}


# Making table of conditions ----------------------------------------------

make_sim_refs <-
  function(conditions = list(T = c(30, 100),
                             N = c(100),
                             Model = c("BinAR", "Chi2AR", "DAR"),
                             l2.dist = c("Gaussian", "Chi2"),
                             phi = c(0.4)
                             ),
           Reps = 100,
           seed = 0,
           save.directory = "self-sim",
           save.refs.filename = paste("sim_refs",
                                      Sys.Date()),
           prefix.sim.datasets = "sim_"){

# allow Reps to be used as a vector of indexes
    if(length(Reps)<2) Reps = seq_len(Reps)


# save global seed of the global env and set it back before leaving
    seed.old <- .Random.seed
    on.exit({
      .Random.seed <<- seed.old
    })

# sorting conditions alphabetically
    conditions <- conditions[order(names(conditions))]

    conditions$sim.Seed <- seed
    conditions$Rep <- Reps

    n.conditions <- length(conditions)

    # making the first columns of the data frame
    d <- conditions %>%
      expand.grid(stringsAsFactors = TRUE)

    # transforming factors to numerics
    d.numeric <- d
    factor.columns <- sapply(d.numeric, is.factor)
    d.numeric[factor.columns] <-
      sapply(d.numeric[factor.columns], as.numeric)

    # getting rid of non-integers and Rep
    d.integer <- d.numeric[, -n.conditions] %>%
      apply(2,
            function(x)
              x %>%
              as.character() %>%
              gsub("\\.", "", .) %>%
              as.numeric())

    # to make unique seeds, we must sum conditions weighted by prime numbers
    # but the primes must not be among prime factors of conditions

    # conditions prime factors
    cpfs <- d.integer %>%
      unlist() %>%
      as.numeric() %>%
      unique() %>%
      primes::prime_factors() %>%
      unlist() %>%
      unique()

    primes.seq <- c(cpfs,
                    primes::generate_n_primes(ncol(d.integer) + length(cpfs)))

    primes.seq <-
      primes.seq[!(duplicated(primes.seq) |
                     duplicated(primes.seq, fromLast = TRUE))]

    uSeed <- d.integer %*% primes.seq %>%
      as.character() %>%
      paste0(as.character(d.numeric$Rep),
             .)

    d.headers <- d %>%
      mutate(
        uSeed = uSeed,
        sim.Path = save.directory,
        sim.File = NA
      ) %>%
      relocate(uSeed, .before = 1)

    for (r in 1:nrow(d.headers)) {
      only.headers <- d.headers %>%
        select(-sim.Path:-sim.File) %>%
        colnames()
      r.values <- d.headers[r, only.headers]
      factor.columns <- sapply(r.values, is.factor)
      r.values[factor.columns] <-
        sapply(r.values[factor.columns], as.character)
      d.headers[r, "sim.File"] <- only.headers %>%
        paste0("-") %>%
        paste0(r.values) %>%
        paste(collapse = "_") %>%
        paste0(".rds") %>%
        paste0(prefix.sim.datasets, .) # prefix for simulated datasets
    }

    d <- d.headers

    # getting rid of factors
    factor.columns <- sapply(d, is.factor)
    d[factor.columns] <-
      sapply(d[factor.columns], as.character)

    # making uSeed numeric
    d$uSeed <- d$uSeed %>% as.numeric()

    # Save the references data frame to a file
    if(!is.null(save.refs.filename)){
      saveRDS(d,
              file = here::here(save.directory, paste0(save.refs.filename,
                                                       ".rds"))
              )
      write.csv(d,
                file = here::here(save.directory, paste0(save.refs.filename,
                                                         ".csv")),
                row.names = FALSE)
    }

    return(d)
}

# Making references of fit files ------------------------------------------

make_fit_refs <-
  function(sim_refs,
           hyperparameters = list(iter = c(2000),
                                  thin = c(5)
                                  ),
           save.directory = "self-sim",
           save.refs.filename = paste("fit_refs",
                                      Sys.Date()),
           prefix.fit.datasets = "fit_"){

    dir.create(save.directory, showWarnings = FALSE)

    nClust <- 48

    h <- hyperparameters %>%
      expand.grid(stringsAsFactors = TRUE)

    dd <- sim_refs[rep(1:nrow(sim_refs), times = nrow(h)),]
    rownames(dd) <- NULL
    hh <- h[rep(1:nrow(h), each = nrow(sim_refs)),]
    rownames(hh) <- NULL

    d <- cbind(dd,hh)
    d <- d %>%
      mutate(fit.Path = save.directory,
             fit.File = NA
      )


    for (r in 1:nrow(d)) {
      only.headers <- names(hyperparameters) %>% c("uSeed",.,"Rep")
      r.values <-d[r, only.headers]
      factor.columns <- sapply(r.values, is.factor)
      r.values[factor.columns] <-
        sapply(r.values[factor.columns], as.character)
      d[r, "fit.File"] <- only.headers %>%
        paste0("-") %>%
        paste0(r.values) %>%
        paste(collapse = "_") %>%
        paste0(".rds") %>%
        paste0(prefix.fit.datasets, .) # prefix for fitted datasets

    }


    if(!is.null(save.refs.filename)){
      saveRDS(d,
              file = here::here(save.directory,
                                paste0(save.refs.filename,
                                       ".rds"))
      )
      write.csv(d,
                file = here::here(save.directory,
                                  paste0(save.refs.filename,
                                         ".csv")),
                row.names = FALSE)
    }

    return(d)
  }


# Simulate in parallel ----------------------------------------------------

make_sim_parallel <-
  function(sim_refs,
           nClust = 48,
           save.directory = "self-sim",
           alternative.sim.Path = NULL,
           clusterLOG.filename = paste("clusterLOG",
                                      Sys.Date()),
           sleeptime = 1 # seconds to wait before runnig clusters
           ){

    cl <- snow::makeSOCKcluster(nClust,
                                outfile = here::here(save.directory,
                                                     "sim_clusterLOG.txt"))
    debug <- TRUE

    d <- sim_refs


    ## Start clusters:

    snow::clusterExport(cl,
                        c("d",
                          "make_population",
                          "alternative.sim.Path",
                          "debug"),
                        envir = environment())

    snow::clusterApplyLB(cl = cl,
                         seq_len(nrow(d)),
                         function(i) {

                           Sys.sleep(sleeptime*(i %% nClust))

                           if (debug) {
                             cat("\nRunning iteration:",
                                 i,
                                 " / ",
                                 nrow(d),
                                 "\nTime:",
                                 as.character(Sys.time()),
                                 "\n")
                             print(d$sim.File)
                           }


                           d_i <- as.list(d[i, ])
                           arguments <-
                             as.list(d_i[2:(length(d_i) - 4)])
                           arguments$seed <- d_i$uSeed

                           sim.Path <- ifelse(is.null(alternative.sim.Path),
                                              d_i$sim.Path,
                                              alternative.sim.Path)

                           sim.StartTime <- Sys.time()

                           tryRes <-
                             try(output.dataset <- do.call(make_population,
                                                           arguments))
                           # if (is(tryRes,"try-error")){
                           #   if (debug){
                           #     browser()
                           #   }
                           #   return(list(error = TRUE, errorMessage = as.character(tryRes), id = d$id[i]))
                           # }
                           d_i$sim.Dataset <- tryRes
                           d_i$sim.StartTime <- sim.StartTime
                           d_i$sim.EndTime <- Sys.time()
                           d_i$sim.ElapsedTime <- d_i$sim.EndTime - d_i$sim.StartTime

                           saveRDS(d_i,
                                   file = here::here(sim.Path,
                                                     d_i$sim.File))

                         })

    # Stop the cluster:
    snow::stopCluster(cl)

  }


# Fit in parallel ---------------------------------------------------------

make_sim_parallel <-
  function(sim_refs,
           nClust = 48,
           save.directory = "self-sim",
           alternative.sim.Path = NULL,
           clusterLOG.filename = paste("clusterLOG",
                                       Sys.Date()),
           sleeptime = 1 # seconds to wait before runnig clusters
  ){

    cl <- snow::makeSOCKcluster(nClust,
                                outfile = here::here(save.directory,
                                                     "sim_clusterLOG.txt"))
    debug <- TRUE

    d <- sim_refs


    ## Start clusters:

    snow::clusterExport(cl,
                        c("d",
                          "make_population",
                          "alternative.sim.Path",
                          "debug"),
                        envir = environment())

    snow::clusterApplyLB(cl = cl,
                         seq_len(nrow(d)),
                         function(i) {

                           Sys.sleep(sleeptime*(i %% nClust))

                           if (debug) {
                             cat("\nRunning iteration:",
                                 i,
                                 " / ",
                                 nrow(d),
                                 "\nTime:",
                                 as.character(Sys.time()),
                                 "\n")
                             print(d$sim.File)
                           }


                           d_i <- as.list(d[i, ])
                           arguments <-
                             as.list(d_i[2:(length(d_i) - 4)])
                           arguments$seed <- d_i$uSeed

                           sim.Path <- ifelse(is.null(alternative.sim.Path),
                                              d_i$sim.Path,
                                              alternative.sim.Path)

                           sim.StartTime <- Sys.time()

                           tryRes <-
                             try(output.dataset <- do.call(make_population,
                                                           arguments))
                           # if (is(tryRes,"try-error")){
                           #   if (debug){
                           #     browser()
                           #   }
                           #   return(list(error = TRUE, errorMessage = as.character(tryRes), id = d$id[i]))
                           # }
                           d_i$sim.Dataset <- tryRes
                           d_i$sim.StartTime <- sim.StartTime
                           d_i$sim.EndTime <- Sys.time()
                           d_i$sim.ElapsedTime <- d_i$sim.EndTime - d_i$sim.StartTime

                           saveRDS(d_i,
                                   file = here::here(sim.Path,
                                                     d_i$sim.File))

                         })

    # Stop the cluster:
    snow::stopCluster(cl)

  }




