

#' Run one or more chains of an MCMC algorithm and extract samples
#'
#' Takes as input an MCMC algorithm (ideally a compiled one for speed)
#' and runs the MCMC with one or more chains, automatically extracting
#' the samples.
#'
#' @param mcmc A NIMBLE MCMC algorithm.  See details.
#'
#' @param niter Number of iterations to run each MCMC chain (default = 10000).
#'
#' @param nburnin Number of initial samples to discard from each MCMC chain (default = 0).
#'
#' @param nchains Number of MCMC chains to run (default = 1).
#'
#' @param inits Optional argument to specify initial values for each chain.  See details.
#'
#' @param setSeed Logical argument.  If \code{TRUE}, then R's random number seed is set to \code{i} (using \code{set.seed(i)}) at the onset of each MCMC chain number \code{i} (default = \code{FALSE}).
#'
#' @param progressBar Logical argument.  If \code{TRUE}, an MCMC progress bar is displayed during execution of each MCMC chain (default = \code{TRUE}).
#'
#' @param silent Logical argument.  If \code{TRUE}, then all output is suppressed during execution.  This overrides the \code{progressBar} argument (default = \code{FALSE}).
#'
#' @param returnCodaMCMC Logical argument.  If \code{TRUE}, then a \code{coda} \code{mcmc} object is returned instead of an R matrix of samples, or when \code{nchains > 1} a \code{coda} \code{mcmc.list} object is returned containing \code{nchains} \code{mcmc} objects (default = \code{FALSE}).
#'
#' @return When \code{nchains = 1}, a matrix of MCMC samples.  When \code{nchains > 1}, a list of length \code{nchains}, where each list element is a matrix of MCMC samples.  If \code{returnCodaMCMC = TRUE}, then a \code{coda} \code{mcmc} or \code{mcmc.list} object is returned instead.
#'
#' @details
#'
#' The \code{mcmc} argument can be a compiled or uncompiled NIMBLE MCMC algorithm, which is generated using \code{buildMCMC}.  Using a compiled algorithm will give substantially faster execution.
#'
#' If provided, the \code{inits} argument can be one of three things:
#' (1) a function to generate initial values, which will be executed to generate initial values at the beginning of each MCMC chain,
#' (2) a single named list of initial values which, will be used for each chain, or
#' (3) a list of length \code{nchains}, each element being a named list of initial values which be used for one MCMC chain.
#' The \code{inits} argument may also be omitted, in which case the current values in the \code{model} object will be used as the initial values of the first chain, and subsequent chains will begin using starting values where the previous chain ended.
#' 
#' Other aspects of the MCMC algorithm, such as sampler assignments and thinning, must be specified in advance using the MCMC configuration object (created using \code{configureMCMC}), which is then used to build the MCMC algorithm (using \code{buildMCMC}) argument.
#'
#' The \code{niter} argument specifies the number of pre-thinning MCMC iterations, and the \code{nburnin} argument will remove post-thinning samples.
#'
#' The MCMC option \code{mcmc$run(..., reset = FALSE)}, used to continue execution of an MCMC chain, is not available through \code{runMCMC()}.
#' 
#' @examples
#' \dontrun{
#' code <- nimbleCode({
#'     mu ~ dnorm(0, sd = 1000)
#'     sigma ~ dunif(0, 1000)
#'     for(i in 1:10) {
#'         x[i] ~ dnorm(mu, sd = sigma)
#'     }
#' })
#' Rmodel <- nimbleModel(code)
#' Rmodel$setData(list(x = c(2, 5, 3, 4, 1, 0, 1, 3, 5, 3)))
#' Rmcmc <- buildMCMC(Rmodel)
#' Cmodel <- compileNimble(Rmodel)
#' Cmcmc <- compileNimble(Rmcmc, project = Rmodel)
#' inits <- function() list(mu = rnorm(1,0,1), sigma = runif(1,0,10))
#' samplesList <- runMCMC(Cmcmc, niter = 10000, nchains = 3, inits = inits)
#' }
#'
#' @seealso \code{\link{configureMCMC}} \code{\link{buildMCMC}}
#'
#' @author Daniel Turek
#'
#' @export
runMCMC <- function(mcmc,
                    niter = 10000, nburnin = 0, nchains = 1,
                    inits,
                    setSeed = FALSE,
                    progressBar = TRUE,
                    silent = FALSE,
                    returnCodaMCMC = FALSE) {
    if(missing(mcmc)) stop('must provide a NIMBLE MCMC algorithm')
    if(!identical(nf_getGeneratorFunction(mcmc), buildMCMC)) stop('mcmc argument must be a NIMBLE MCMC algorithm')
    if(!is.Cnf(mcmc)) message('Warning: running an uncompiled MCMC algorithm, use compileNimble() for faster execution.')
    if(nchains < 1) stop('must have nchains > 0')
    if(!missing(inits)) {
        if(!is.function(inits) && !is.list(inits)) stop('inits must be a function, a list of initial values, or a list (of length nchains) of lists of inital values')
        if(is.list(inits) && is.list(inits[[1]]) && (length(inits) != nchains)) stop('inits must be a function, a list of initial values, or a list (of length nchains) of lists of inital values')
    }
    model <- if(is.Cnf(mcmc)) mcmc$Robject$model$CobjectInterface else mcmc$model
    if(!inherits(model, 'modelBaseClass')) stop('something went wrong')
    samplesList <- vector('list', nchains)
    for(i in 1:nchains) {
        if(!silent) message('running chain ', i, '...')
        if(setSeed) set.seed(i)
        if(!missing(inits)) {
            if(is.function(inits)) {
                theseInits <- inits()
            } else if(is.list(inits[[1]])) {
                theseInits <- inits[[i]]
            } else theseInits <- inits
            model$setInits(theseInits)
        }
        model$calculate()
        mcmc$run(niter, progressBar = progressBar && !silent)
        samples <- as.matrix(mcmc$mvSamples)
        if(nburnin > 0) samples <- samples[-(1:nburnin), , drop = FALSE]
        samplesList[[i]] <- samples
    }
    if(returnCodaMCMC) samplesList <- coda::as.mcmc.list(lapply(samplesList, coda::as.mcmc))
    if(nchains == 1) samplesList <- samplesList[[1]]  ## returns matrix when nchains=1
    return(samplesList)
}


