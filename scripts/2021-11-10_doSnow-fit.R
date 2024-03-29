library(doSNOW)
library(tidyverse)
# rm(list=ls())

############################################################
### First un first 75 lines of 2021-11-10_fit-experiment-b.R
############################################################

# removing the fitted models from fitting
d.references_all <- d
us <- list.files("self-sim/experiment-b/", "fit_uSeed-")

d <- d %>%
  filter(!(fit.File %in% us)) %>%
  filter(Rep %in% c(1:100, 501:700))

# d <- d_100.to.200

# From https://biostat.app.vumc.org/wiki/pub/Main/MinchunZhou/HPC_ --------

debug <- TRUE

Sys.time()
nClust <- 48
t.fit <- system.time({
  cl <- makeCluster(nClust)
  registerDoSNOW(cl)
  t.snow <- snow.time({
    foreach(i = 1:nrow(d)) %dopar% {
      source(here::here("functions",
                        "functions_Mplus.R"))

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

      # arguments <- split(d[1,1:length(conditions)],
      #                    1)[[1]] %>%
      #   as.list()
      d_i <- as.list(d[i, ])

      fit.StartTime <- Sys.time()

      # tryRes <-
      #   try(output.dataset <- run_MplusAutomation()
      # if (is(tryRes,"try-error")){
      #   if (debug){
      #     browser()
      #   }
      #   return(list(error = TRUE, errorMessage = as.character(tryRes), id = d$id[i]))
      # }

      df <- readRDS(file = here::here(d_i$sim.Path,
                                      d_i$sim.File))$sim.Dataset
      file.name <- gsub(".rds", "", d_i$fit.File)

      tryRes <-
        try(
      output.fit <- run_MplusAutomation(df = df,
                                        PROCESSORS = 1,
                                        BITERATIONS.min = d_i$iter,
                                        THIN = d_i$thin,
                                        file.name = file.name)
        )

      d_i$fit.Dataset <- tryRes # output.fit
      d_i$fit.StartTime <- fit.StartTime
      d_i$fit.EndTime <- Sys.time()
      d_i$fit.ElapsedTime <- d_i$sim.EndTime - d_i$sim.StartTime

      saveRDS(d_i,
              file = here::here(d_i$fit.Path, d_i$fit.File))

      return(paste("Running iteration:",
                   i,
                   " / ",
                   nrow(d),
                   "Time:",
                   as.character(Sys.time())))

    }
  })
  stopCluster(cl)
})

t.fit
Sys.time()
saveRDS(t.snow, "t.snow_1.to.100_501.to.700.rds")
t.snow
plot(t.snow)
