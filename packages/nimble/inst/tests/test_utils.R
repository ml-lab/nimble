### Functions for testing math, called from test_math.R
require(testthat)
require(methods)
require(nimble)

## We can get problems on Windows with system(cmd) if cmd contains
## paths with spaces in directory names.  Solution is to make a cmd
## string with only local names (to avoid spaces) and indicate what
## directory it should be done in.  setwd(dir) should handle dir with
## paths with spaces ok.
system.in.dir <- function(cmd, dir = '.') {
    curDir <- getwd()
    on.exit(setwd(curDir))
    setwd(dir)
    if(.Platform$OS.type == "windows")
        shell(shQuote(cmd))
    else
        system(cmd)
}

gen_runFun <- function(input) {
  runFun <- function() {}
  formalsList <- vector('list', length(input$inputDim))
  formalsList <- lapply(input$inputDim, function(x) parse(text = paste0("double(", x, ")"))[[1]])
  names(formalsList) <- paste0('arg', seq_along(input$inputDim))
  formals(runFun) <- formalsList
  tmp <- quote({})
  tmp[[2]] <- input$expr
  tmp[[3]] <- quote(return(out))
  tmp[[4]] <- parse(text = paste0("returnType(double(", input$outputDim, "))"))[[1]]
  body(runFun) <- tmp
  return(runFun)
}

make_input <- function(dim, size = 3, logicalArg) {
  if(!logicalArg) rfun <- rnorm else rfun <- function(n) { rbinom(n, 1, .5) }
  if(dim == 0) return(rfun(1))
  if(dim == 1) return(rfun(size))
  if(dim == 2) return(matrix(rfun(size^2), size))
  stop("not set for dimension greater than 2")
}

test_math <- function(input, verbose = TRUE, size = 3) {
  if(verbose) cat("### Testing", input$name, "###\n")
  runFun <- gen_runFun(input)
  nfR <- nimbleFunction(  # formerly nfGen
      #       setup = TRUE,
             run = runFun)
  #nfR <- nfGen()
  project <- nimble:::nimbleProjectClass(NULL, name = 'foo')
  nfC <- compileNimble(nfR, project = project)

  nArgs <- length(input$inputDim)
  logicalArgs <- rep(FALSE, nArgs)
  if("logicalArgs" %in% names(input))
    logicalArgs <- input$logicalArgs

  arg1 <- make_input(input$inputDim[1], size = size, logicalArgs[1])
  if(nArgs == 2)
    arg2 <- make_input(input$inputDim[2], size = size, logicalArgs[2])
  if("Rcode" %in% names(input)) {
    eval(input$Rcode)
  } else {
    eval(input$expr)
  }
  if(nArgs == 2) {
    out_nfR = nfR(arg1, arg2)
    out_nfC = nfC(arg1, arg2)
  } else {
    out_nfR = nfR(arg1)
    out_nfC = nfC(arg1)
  }
  attributes(out) <- attributes(out_nfR) <- attributes(out_nfC) <- NULL
  if(is.logical(out)) out <- as.numeric(out)
  if(is.logical(out_nfR)) out_nfR <- as.numeric(out_nfR)
  try(test_that(paste0("Test of math (direct R calc vs. R nimbleFunction): ", input$name),
                expect_equal(out, out_nfR)))
  try(test_that(paste0("Test of math (direct R calc vs. C nimbleFunction): ", input$name),
                expect_equal(out, out_nfC)))
  # unload DLL as R doesn't like to have too many loaded
  if(.Platform$OS.type != 'windows') dyn.unload(project$cppProjects[[1]]$getSOName())
  invisible(NULL)
}


### Function for testing MCMC called from test_mcmc.R

test_mcmc <- function(example, model, data = NULL, inits = NULL,
                      verbose = TRUE, numItsR = 5, numItsC = 1000,
                      basic = TRUE, exactSample = NULL, results = NULL, resultsTolerance = NULL,
                      numItsC_results = numItsC,
                      resampleData = FALSE,
                      topLevelValues = NULL, seed = 0, mcmcControl = NULL, samplers = NULL, removeAllDefaultSamplers = FALSE,
                      doR = TRUE, doCpp = TRUE, returnSamples = FALSE, name = NULL) {
  # There are three modes of testing:
  # 1) basic = TRUE: compares R and C MCMC values and, if requested by passing values in 'exactSample', will compare results to actual samples (you'll need to make sure the seed matches what was used to generate those samples)
  # 2) if you pass 'results', it will compare MCMC output to known posterior summaries within tolerance specified in resultsTolerance
  # 3) resampleData = TRUE: runs initial MCMC to get top level nodes then simulates from the rest of the model, including data, to get known parameter values, and fits to the new data, comparing parameter estimates from MCMC with the known parameter values

    # samplers can be given individually for each node of interest or as a vector of nodes for univariate samplers or list of vectors of nodes for multivariate samplers
    # e.g.,
    # multiple univar samplers: samplers(type = 'RW', target = c('mu', 'x'))
    # single multivar sampler: samplers(type = "RW_block", target = c('x[1]', 'x[2]'))
    # single multivar sampler: samplers(type = "RW_block", target = 'x')
    # multiple multivar samplers: samplers(type = "RW_block", target = list('x', c('theta', 'mu')))

    
    setSampler <- function(var, conf) {
        currentTargets <- sapply(conf$samplerConfs, function(x) x$target)
                                        # remove already defined scalar samplers
        inds <- which(unlist(var$target) %in% currentTargets)
        conf$removeSamplers(inds, print = FALSE)
                                        # look for cases where one is adding a blocked sampler specified on a variable and should remove scalar samplers for constituent nodes
        currentTargets <- sapply(conf$samplerConfs, function(x) x$target)
        inds <- which(sapply(unlist(var$target), function(x) Rmodel$expandNodeNames(x)) %in% currentTargets)
                                        #      inds <- which(sapply(conf$samplerConfs, function(x)
                                        #          gsub("\\[[0-9]+\\]", "", x$target))
                                        #                         %in% var$target)
        conf$removeSamplers(inds, print = FALSE)
        
        if(is.list(var$target) && length(var$target) == 1) var$target <- var$target[[1]]
        if(length(var$target) == 1 || (var$type %in% c("RW_block", "RW_PF_block", "RW_llFunction_block") && !is.list(var$target))) 
            tmp <- conf$addSampler(type = var$type, target = var$target, control = var$control, print = FALSE) else tmp <- sapply(var$target, function(x) conf$addSampler(type = var$type, target = x, control = var$control, print = FALSE))
    }

    if(is.null(name)) {
        if(!missing(example)) {
            name <- example
        } else {
            if(is.character(model)) {
                name <- model
            } else {
                name <- 'unnamed case'
            }
        }
    }

    cat("===== Starting MCMC test for ", name, ". =====\n", sep = "")

    if(!missing(example)) {
                                        # classic-bugs example specified by name
  	dir = nimble:::getBUGSexampleDir(example)
        if(missing(model)) model <- example
        Rmodel <- readBUGSmodel(model, dir = dir, data = data, inits = inits, useInits = TRUE,
                                check = FALSE)
    } else {
                                        # code, data and inits specified directly where 'model' contains the code
        example = deparse(substitute(model))
        if(missing(model)) stop("Neither BUGS example nor model code supplied.")
        Rmodel <- readBUGSmodel(model, data = data, inits = inits, dir = "", useInits = TRUE,
                                check = FALSE)
    }

  if(doCpp) {
      Cmodel <- compileNimble(Rmodel)
      cat('done compiling model\n')
  }
  if(!is.null(mcmcControl)) mcmcConf <- configureMCMC(Rmodel, control = mcmcControl) else mcmcConf <- configureMCMC(Rmodel)
  if(removeAllDefaultSamplers) mcmcConf$removeSamplers()
  
  if(!is.null(samplers)) {
      sapply(samplers, setSampler, mcmcConf)
      if(verbose) {
          cat("Setting samplers to:\n")
          print(mcmcConf$getSamplers())
      }
  }

  vars <- Rmodel$getDependencies(Rmodel$getNodeNames(topOnly = TRUE, stochOnly = TRUE), stochOnly = TRUE, includeData = FALSE, downstream = TRUE)
  vars <- unique(nimble:::removeIndexing(vars))
  mcmcConf$addMonitors(vars, print = FALSE)
  
  Rmcmc <- buildMCMC(mcmcConf)
  if(doCpp) {
      Cmcmc <- compileNimble(Rmcmc, project = Rmodel)
  }

  if(basic) {
    ## do short runs and compare R and C MCMC output
      if(doR) {
          set.seed(seed);
          RmcmcOut <- try(Rmcmc$run(numItsR))
          if(!is(RmcmcOut, "try-error")) {
            RmvSample  <- nfVar(Rmcmc, 'mvSamples')
            R_samples <- as.matrix(RmvSample)
          } else R_samples <- NULL
      }
      if(doCpp) {
          set.seed(seed)
          Cmcmc$run(numItsC)
          CmvSample <- nfVar(Cmcmc, 'mvSamples')
          C_samples <- as.matrix(CmvSample)
          ## for some reason columns in different order in CmvSample...
          C_subSamples <- C_samples[seq_len(numItsR), attributes(R_samples)$dimnames[[2]], drop = FALSE]
      }

      if(doR && doCpp && !is.null(R_samples)) {
          context(paste0("testing ", example, " MCMC"))
          try(
              test_that(paste0("test of equality of output from R and C versions of ", example, " MCMC"), {
                  expect_equal(R_samples, C_subSamples, info = paste("R and C posterior samples are not equal"))
              })
              )
      }
      if(is.null(R_samples)) {
          cat("R MCMC failed.\n")
      }

      if(doCpp) {
          if(!is.null(exactSample)) {
              for(varName in names(exactSample))
                  try(
                      test_that(paste("Test of MCMC result against known samples for", example, ":", varName), {
                          expect_equal(round(C_samples[seq_along(exactSample[[varName]]), varName], 8), round(exactSample[[varName]], 8)) })
                      )
          }
      }

    summarize_posterior <- function(vals)
      return(c(mean = mean(vals), sd = sd(vals), quantile(vals, .025), quantile(vals, .975)))

      if(doCpp) {
          if(verbose) {
              start <- round(numItsC / 2) + 1
              try(print(apply(C_samples[start:numItsC, , drop = FALSE], 2, summarize_posterior)))
          }
      }
  }

  ## assume doR and doCpp from here down
  if(!is.null(results)) {
     # do (potentially) longer run and compare results to inputs given
    set.seed(seed)
    Cmcmc$run(numItsC_results)
    CmvSample <- nfVar(Cmcmc, 'mvSamples')
    postBurnin <- (round(numItsC_results/2)+1):numItsC_results
    C_samples <- as.matrix(CmvSample)[postBurnin, , drop = FALSE]
     for(metric in names(results)) {
      if(!metric %in% c('mean', 'median', 'sd', 'var', 'cov'))
        stop("Results input should be named list with the names indicating the summary metrics to be assessed, from amongst 'mean', 'median', 'sd', 'var', and 'cov'.")
      if(metric != 'cov') {
        postResult <- apply(C_samples, 2, metric)
        for(varName in names(results[[metric]])) {
          varName <- gsub("_([0-9]+)", "\\[\\1\\]", varName) # allow users to use theta_1 instead of "theta[1]" in defining their lists
          samplesNames <- dimnames(C_samples)[[2]]
          if(!grepl(varName, "\\[", fixed = TRUE))
             samplesNames <- gsub("\\[.*\\]", "", samplesNames)
          matched <- which(varName == samplesNames)
          diff <- abs(postResult[matched] - results[[metric]][[varName]])
          for(ind in seq_along(diff)) {
            strInfo <- ifelse(length(diff) > 1, paste0("[", ind, "]"), "")
            try(
              test_that(paste("Test of MCMC result against known posterior for", example, ":",  metric, "(", varName, strInfo, ")"), {
                expect_lt(diff[ind], resultsTolerance[[metric]][[varName]][ind])
              })
              )
          }
        }
      } else  { # 'cov'
        for(varName in names(results[[metric]])) {
          matched <- grep(varName, dimnames(C_samples)[[2]], fixed = TRUE)
          postResult <- cov(C_samples[ , matched])
           # next bit is on vectorized form of matrix so a bit awkward
          diff <- c(abs(postResult - results[[metric]][[varName]]))
          for(ind in seq_along(diff)) {
            strInfo <- ifelse(length(diff) > 1, paste0("[", ind, "]"), "")
            try(
              test_that(paste("Test of MCMC result against known posterior for", example, ":",  metric, "(", varName, ")", strInfo), {
                expect_lt(diff[ind], resultsTolerance[[metric]][[varName]][ind])
              })
              )
          }
        }
      }
    }
  }
  if(returnSamples) {
    if(exists('CmvSample'))
      returnVal <- as.matrix(CmvSample)
  } else returnVal <- NULL

  if(resampleData) {
    topNodes <- Rmodel$getNodeNames(topOnly = TRUE, stochOnly = TRUE)
    topNodesElements <- Rmodel$getNodeNames(topOnly = TRUE, stochOnly = TRUE,
                                            returnScalarComponents = TRUE)
    if(is.null(topLevelValues)) {
      postBurnin <- (round(numItsC/2)):numItsC
      if(is.null(results) && !basic) {
      # need to generate top-level node values so do a basic run
        set.seed(seed)
        Cmcmc$run(numItsC)
        CmvSample <- nfVar(Cmcmc, 'mvSamples')
        C_samples <- as.matrix(CmvSample)[postBurnin, ]
      }
      topLevelValues <- as.list(apply(C_samples[ , topNodesElements, drop = FALSE], 2, mean))
    }
    if(!is.list(topLevelValues)) {
      topLevelValues <- as.list(topLevelValues)
      if(sort(names(topLevelValues)) != sort(topNodesElements))
        stop("Values not provided for all top level nodes; possible name mismatch")
    }
    sapply(topNodesElements, function(x) Cmodel[[x]] <- topLevelValues[[x]])
    # check this works as side effect
    nontopNodes <- Rmodel$getDependencies(topNodes, self = FALSE, includeData = TRUE, downstream = TRUE, stochOnly = FALSE)
    # nonDataNodes <- Rmodel$getDependencies(topNodes, self = TRUE, includeData = FALSE, downstream = TRUE, stochOnly = TRUE)
    nonDataNodesElements <- Rmodel$getDependencies(topNodes, self = TRUE, includeData = FALSE, downstream = TRUE, stochOnly = TRUE, returnScalarComponents = TRUE)
    dataVars <- unique(nimble:::removeIndexing(Rmodel$getDependencies(topNodes, dataOnly = TRUE, downstream = TRUE)))
    set.seed(seed)
    Cmodel$resetData()
    simulate(Cmodel, nontopNodes)

    dataList <- list()
    for(var in dataVars) {
      dataList[[var]] <- values(Cmodel, var)
      if(Cmodel$modelDef$varInfo[[var]]$nDim > 1)
        dim(dataList[[var]]) <- Cmodel$modelDef$varInfo[[var]]$maxs
    }
    Cmodel$setData(dataList)

    trueVals <- values(Cmodel, nonDataNodesElements)
    names(trueVals) <- nonDataNodesElements
    set.seed(seed)
    Cmcmc$run(numItsC_results)
    CmvSample <- nfVar(Cmcmc, 'mvSamples')

    postBurnin <- (round(numItsC_results/2)):numItsC
    C_samples <- as.matrix(CmvSample)[postBurnin, nonDataNodesElements, drop = FALSE]
    interval <- apply(C_samples, 2, quantile, c(.025, .975))
    interval <- interval[ , names(trueVals)]
    covered <- trueVals <= interval[2, ] & trueVals >= interval[1, ]
    coverage <- sum(covered) / length(nonDataNodesElements)
    tolerance <- 0.15
    if(verbose)
      cat("Coverage for model", example, "is", coverage*100, "%.\n")
    miscoverage <- abs(coverage - 0.95)
    try(
      test_that(paste("Test of MCMC coverage on known parameter values for:", example), {
                expect_lt(miscoverage, tolerance)
              })
      )
    if(miscoverage > tolerance || verbose) {
      cat("True values with 95% posterior interval:\n")
      print(cbind(trueVals, t(interval), covered))
    }
  }

  cat("===== Finished MCMC test for ", name, ". =====\n", sep = "")

    if(doCpp) {
        if(.Platform$OS.type != "windows") {
            dyn.unload(getNimbleProject(Rmodel)$cppProjects[[1]]$getSOName()) ## Rmodel and Rmcmc have the same project so they are interchangeable in these lines.
            dyn.unload(getNimbleProject(Rmcmc)$cppProjects[[2]]$getSOName())  ## Really it is the [[1]] and [[2]] that matter
            }
    }
  return(returnVal)
}


test_filter <- function(example, model, data = NULL, inits = NULL,
                        verbose = TRUE, numItsR = 5, numItsC = 10000,
                        basic = TRUE, exactSample = NULL, results = NULL, resultsTolerance = NULL,
                        numItsC_results = numItsC,
                        seed = 0, filterType = NULL, latentNodes = NULL, filterControl = NULL,
                        doubleCompare = FALSE, filterType2 = NULL,
                        doR = TRUE, doCpp = TRUE, returnSamples = FALSE, name = NULL) {
  # There are two modes of testing:
  # 1) basic = TRUE: compares R and C Particle Filter likelihoods and sampled states
  # 2) if you pass 'results', it will compare Filter output to known latent state posterior summaries, top-level parameter posterior summaries,
  #    and likelihoods within tolerance specified in resultsTolerance.  Results are compared for both weighted and unweighted samples.
  # filterType determines which filter to use for the model.  Valid options are: "bootstrap", "auxiliary", "LiuWest", "ensembleKF"
  # filterControl specifies options to filter function, such as saveAll = TRUE/FALSE.

  if(is.null(name)) {
    if(!missing(example)) {
      name <- example
    } else {
      if(is.character(model)) {
        name <- model
      } else {
        name <- 'unnamed case'
      }
    }
  }

  cat("===== Starting Filter test for ", name, " using ", filterType, ". =====\n", sep = "")

  if(!missing(example)) {
    # classic-bugs example specified by name
    dir = getBUGSexampleDir(example)
    if(missing(model)) model <- example
    Rmodel <- readBUGSmodel(model, dir = dir, data = data, inits = inits, useInits = TRUE, check = FALSE)
  } else {
    # code, data and inits specified directly where 'model' contains the code
    example = deparse(substitute(model))
    if(missing(model)) stop("Neither BUGS example nor model code supplied.")
    Rmodel <- readBUGSmodel(model, dir = "", data = data, inits = inits, useInits = TRUE, check = FALSE)
  }
  if(doCpp) {
    Cmodel <- compileNimble(Rmodel)
    cat('done compiling model\n')
  }
  cat("Building filter\n")
  if(filterType == "bootstrap"){
    if(!is.null(filterControl))  Rfilter <- buildBootstrapFilter(Rmodel, nodes = latentNodes, control = filterControl)
    else Rfilter <- buildBootstrapFilter(Rmodel, nodes = latentNodes, control = list(saveAll = TRUE, thresh = 0))
  }
  if(filterType == "auxiliary"){
    if(!is.null(filterControl))  Rfilter <- buildAuxiliaryFilter(Rmodel, nodes = latentNodes, control = filterControl)
    else Rfilter <- buildAuxiliaryFilter(Rmodel, nodes = latentNodes, control = list(saveAll = TRUE))
  }
  if(filterType == "LiuWest"){
    if(!is.null(filterControl))  Rfilter <- buildLiuWestFilter(Rmodel, nodes = latentNodes, control = filterControl)
    else Rfilter <- buildLiuWestFilter(Rmodel, nodes = latentNodes, control = list(saveAll = TRUE))
  }
  if(filterType == "ensembleKF"){
    if(!is.null(filterControl))  Rfilter <- buildEnsembleKF(Rmodel, nodes = latentNodes, control = filterControl)
    else Rfilter <- buildEnsembleKF(Rmodel, nodes = latentNodes, control = list(saveAll = TRUE))
  }

  if(doCpp) {
    Cfilter <- compileNimble(Rfilter, project = Rmodel)
  }

  if(basic) {
    ## do short runs and compare R and C filter output
    if(doR) {
      set.seed(seed);
      RfilterOut <- try(Rfilter$run(numItsR))
      if(!is(RfilterOut, "try-error")) {
        if(filterType == "ensembleKF"){
          RmvSample  <- nfVar(Rfilter, 'mvSamples')
          R_samples <- as.matrix(RmvSample)
        }
        else{
          RmvSample  <- nfVar(Rfilter, 'mvWSamples')
          RmvSample2 <- nfVar(Rfilter, 'mvEWSamples')
          R_samples <- as.matrix(RmvSample)
          R_samples2 <- as.matrix(RmvSample2)
        }
      } else R_samples <- NULL
    }
    if(doCpp) {
      set.seed(seed)
      CfilterOut <- Cfilter$run(numItsR)
      if(filterType == "ensembleKF"){
        CmvSample <- nfVar(Cfilter, 'mvSamples')
        C_samples <- as.matrix(CmvSample)
        C_subSamples <- C_samples[, attributes(R_samples)$dimnames[[2]], drop = FALSE]
      }
      else{
        CmvSample <- nfVar(Cfilter, 'mvWSamples')
        CmvSample2 <- nfVar(Cfilter, 'mvEWSamples')
        C_samples <- as.matrix(CmvSample)
        C_samples2 <- as.matrix(CmvSample2)
        C_subSamples <- C_samples[, attributes(R_samples)$dimnames[[2]], drop = FALSE]
        C_subSamples2 <- C_samples2[, attributes(R_samples2)$dimnames[[2]], drop = FALSE]
      }


      ## for some reason columns in different order in CmvSample...
    }
    if(doR && doCpp && !is.null(R_samples)) {
      context(paste0("testing ", example," ", filterType, " filter"))
      if(filterType == "ensembleKF"){
        try(
          test_that(paste0("test of equality of output from R and C versions of ", example," ", filterType, " filter"), {
            expect_equal(R_samples, C_subSamples, info = paste("R and C posterior samples are not equal"))
          })
        )
      }
      else{
        try(
          test_that(paste0("test of equality of output from R and C versions of ", example," ", filterType, " filter"), {
            expect_equal(R_samples, C_subSamples, info = paste("R and C weighted posterior samples are not equal"))
            expect_equal(R_samples2, C_subSamples2, info = paste("R and C equally weighted posterior samples are not equal"))
            expect_equal(RfilterOut, CfilterOut, info = paste("R and C log likelihood estimates are not equal"))
          })
        )
      }
    }

    if(is.null(R_samples)) {
      cat("R Filter failed.\n")
    }
    if(doCpp) {
      if(!is.null(exactSample)) {
        for(varName in names(exactSample))
          try(
            test_that(paste("Test of filter result against known samples for", example, ":", varName), {
              expect_equal(round(C_samples[seq_along(exactSample[[varName]]), varName], 8), round(exactSample[[varName]], 8)) })
          )
      }
    }

    summarize_posterior <- function(vals)
      return(c(mean = mean(vals), sd = sd(vals), quantile(vals, .025), quantile(vals, .975)))

    if(doCpp) {
      if(verbose) {
        try(print(apply(C_samples[, , drop = FALSE], 2, summarize_posterior)))
      }
    }
  }

  # assume doR and doCpp from here down
  if(!is.null(results)) {
    # do (potentially) longer run and compare results to inputs given
    set.seed(seed)
    Cll <- Cfilter$run(numItsC_results)
    for(wMetric in c(TRUE, FALSE)){
      weightedOutput <- 'unweighted'
      if(filterType == "ensembleKF")
        CfilterSample <- nfVar(Cfilter, 'mvSamples')
      else{
        if(wMetric){
          CfilterSample <- nfVar(Cfilter, 'mvWSamples')
          weightedOutput <-"weighted"
        }
        else
          CfilterSample <- nfVar(Cfilter, 'mvEWSamples')
      }

      C_samples <- as.matrix(CfilterSample)[, , drop = FALSE]
      if(weightedOutput == "weighted"){
        wtIndices <- grep("^wts\\[", dimnames(C_samples)[[2]])
        C_weights <- as.matrix(C_samples[,wtIndices, drop = FALSE])
        C_samples <- as.matrix(C_samples[,-wtIndices, drop = FALSE])
      }
      latentNames <- Rmodel$expandNodeNames(latentNodes, sort = TRUE, returnScalarComponents = TRUE)
      if(weightedOutput == "weighted"){
        samplesToWeightsMatch <- rep(dim(C_weights)[2], dim(C_samples)[2])
        latentIndices <- match(latentNames, dimnames(C_samples)[[2]])
        latentSampLength <- length(latentNames)
        latentDim <- latentSampLength/dim(C_weights)[2]
        samplesToWeightsMatch[latentIndices] <- rep(1:dim(C_weights)[2], each = latentDim )

      }
      for(metric in names(results)) {
        if(!metric %in% c('mean', 'median', 'sd', 'var', 'cov', 'll'))
          stop("Results input should be named list with the names indicating the summary metrics to be assessed, from amongst 'mean', 'median', 'sd', 'var', 'cov', and 'll'.")
        if(!(metric %in% c('cov', 'll'))) {
          if(weightedOutput == "weighted"){
            postResult <- sapply(1:dim(C_samples)[2], weightedMetricFunc, metric = metric, weights = C_weights, samples = C_samples, samplesToWeightsMatch)
          }
          else
            postResult <- apply(C_samples, 2, metric)
          for(varName in names(results[[metric]])) {
            varName <- gsub("_([0-9]+)", "\\[\\1\\]", varName) # allow users to use theta_1 instead of "theta[1]" in defining their lists
            samplesNames <- dimnames(C_samples)[[2]]
            if(!grepl(varName, "\\[", fixed = TRUE))
              samplesNames <- gsub("\\[.*\\]", "", samplesNames)
            matched <- which(varName == samplesNames)
            diff <- abs(postResult[matched] - results[[metric]][[varName]])
            for(ind in seq_along(diff)) {
              strInfo <- ifelse(length(diff) > 1, paste0("[", ind, "]"), "")
              try(
                test_that(paste("Test of ", filterType, " filter posterior result against known posterior for", example, ":", weightedOutput,  metric, "(", varName, strInfo, ")"), {
                  expect_lt(diff[ind], resultsTolerance[[metric]][[varName]][ind])
                })
              )
            }
          }
        } else if (metric == 'cov' ) {
          for(varName in names(results[[metric]])) {
            matched <- grep(varName, dimnames(C_samples)[[2]], fixed = TRUE)
            #             if(weightedOutput == "weighted")
            #               postResult <- cov.wt(C_samples[, matched], wt = )  #weighted covariance not currently implemented
            #             else
            postResult <- cov(C_samples[ , matched])
            # next bit is on vectorized form of matrix so a bit awkward
            diff <- c(abs(postResult - results[[metric]][[varName]]))
            for(ind in seq_along(diff)) {
              strInfo <- ifelse(length(diff) > 1, paste0("[", ind, "]"), "")
              try(
                test_that(paste("Test of ", filterType, " filter posterior result against known posterior for", example, ":",  metric, "(", varName, ")", strInfo), {
                  expect_lt(diff[ind], resultsTolerance[[metric]][[varName]][ind])
                })
              )
            }
          }
        }
        else{  # ll (log likelihood)
          diff <- abs(Cll - results[[metric]][[1]][1])
          try(
            test_that(paste("Test of ", filterType, " filter log-likelihood result against known log-likelihood for", example, ":",  metric), {
              expect_lt(diff, resultsTolerance[[metric]][[1]][1])
            })
          )
        }
      }
    }
  }
  if(returnSamples) {
    if(exists('CmvSample'))
      returnVal <- as.matrix(CmvSample)
  } else returnVal <- NULL


  cat("===== Finished ", filterType, " filter test for ", name, ". =====\n", sep = "")

    if(doCpp) {
        if(.Platform$OS.type != 'windows') {
            dyn.unload(getNimbleProject(Rmodel)$cppProjects[[1]]$getSOName()) ## Rmodel and Rfilter have the same project so they are interchangeable in these lines.
            dyn.unload(getNimbleProject(Rmodel)$cppProjects[[2]]$getSOName())  ## Really it is the [[1]] and [[2]] that matter
        }
    }
  return(returnVal)
}

weightedMetricFunc <- function(index, samples, weights, metric, samplesToWeightsMatch){
  samples <- samples[,index]
  weights <- exp(weights[,samplesToWeightsMatch[index]])/sum(exp(weights[,samplesToWeightsMatch[index]]))
  if(metric == "median"){
    ord <- order(samples)
    weights <- weights[ord]
    samples <- samples[ord]
    sumWts <- 0
    while(sumWts < .5){
      sumWts <- sumWts + weights[1]
      weights <- weights[-1]
    }
    return(samples[length(samples)-length(weights)])
  }
  wtMean <- weighted.mean(samples, weights)
  if(metric == "mean"){
    return(wtMean)
  }
  wtVar <- sum(weights*(samples - wtMean)^2)
  if(metric == "var"){
    return(wtVar)
  }
  if(metric == "sd"){
    return(sqrt(wtVar))
  }
}

test_size <- function(input, verbose = TRUE) {
    errorMsg <- paste0(ifelse(input$knownProblem, "KNOWN ISSUE: ", ""), "Result does not match ", input$expectPass)
    if(verbose) cat("### Testing", input$name, " with RHS variable ###\n")
    result <- try(
        m <- nimbleModel(code = input$expr, data = input$data, inits = input$inits)
    )
    try(test_that(paste0("Test 1 of size/dimension check: ", input$name),
                  expect_equal(!is(result, "try-error"), input$expectPass,
                              info = errorMsg)))
    if(!is(result, "try-error")) {
        result <- try(
            { calculate(m); out <- calculate(m)} )
        try(test_that(paste0("Test 2 of size/dimension check: ", input$name),
                      expect_equal(!is(result, "try-error"), input$expectPass,
                                  info = errorMsg)))
    }
    if(verbose) cat("### Testing", input$name, "with RHS constant ###\n")
    if(!is.null(input$expectPassWithConst)) input$expectPass <- input$expectPassWithConst
    result <- try(
        m <- nimbleModel(code = input$expr, data = input$data, constants = input$inits)
    )
    try(test_that(paste0("Test 3 of size/dimension check: ", input$name),
                  expect_equal(!is(result, "try-error"), input$expectPass,
                              info = errorMsg)))
    if(!is(result, "try-error")) {
        result <- try(
            { calculate(m); out <- calculate(m)} )
        try(test_that(paste0("Test 4 of size/dimension check: ", input$name),
                      expect_equal(!is(result, "try-error"), input$expectPass,
                                  info = errorMsg)))
    }
    invisible(NULL)
}
