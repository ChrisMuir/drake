#' @title List the available drake triggers.
#' @export
#' @seealso [drake_plan()], [make()]
#' @description Triggers are target-level rules
#' that tell [make()] how to know if a target
#' is outdated or up to date.
#' @return A character vector with the names of the available triggers.
#' @details By default, `make()`
#' builds targets that need updating and
#' skips over the ones that are already up to date.
#' In other words, a change in a dependency, workflow plan command,
#' or file, or the lack of the target itself,
#'*triggers* the build process for the target.
#' You can relax this behavior by choosing a trigger for each target.
#' Set the trigger for each target with a `"trigger"`
#' column in your workflow plan data frame. The `triggers()`
#' function lists the available triggers:
#'
#' \itemize{
#'   \item{'any'}{:
#'     Build the target if any of the other triggers activate (default).
#'   }
#'
#'   \item{'command'}{:
#'     Build if the workflow plan command has changed since last
#'     time the target was built. Also built if `missing` is triggered.
#'   }
#'
#'   \item{'depends'}{:
#'     Build if any of the target's dependencies
#'     has changed since the last [make()].
#'     Also build if `missing` is triggered.
#'   }
#'
#'   \item{'file'}{:
#'     Build if the target is a file and
#'     that output file is either missing or corrupted.
#'     Also build if `missing` is triggered.
#'   }
#'
#'   \item{'missing'}{:
#'     Build if the target itself is missing. Always applies.
#'   }
#' }
#'
#' @examples
#' triggers()
#' \dontrun{
#' test_with_dir("Quarantine side effects.", {
#' load_basic_example() # Load drake's canonical example.
#' my_plan[["trigger"]] <- "command"
#' # You can have different triggers for different targets.
#' my_plan[["trigger"]][1] <- "file"
#' make(my_plan) # Run the project, build the targets.
#' # Change an imported dependency function.
#' reg2 <- function(d) {
#'   d$x3 <- d$x ^ 3
#'   lm(y ~ x3, data = d)
#' }
#' # Nothing changes! To react to `reg2`, you would need the
#' # "any" or "depends" trigger.
#' make(my_plan)
#' # You can use a global trigger if your workflow plan
#' # does not have a 'trigger' column.
#' my_plan[["trigger"]] <- NULL # Would override the global trigger.
#' make(my_plan, trigger = "missing") # Just build missing targets.
#' })
#' }
triggers <- function(){
  c(
    "any",
    "always",
    "command",
    "depends",
    "file",
    "missing"
  ) %>%
    sort
}

#' @title Return the default trigger.
#' @description Triggers are target-level rules
#' that tell [make()] how to check if
#' target is up to date or outdated.
#' @export
#' @seealso [triggers()], [make()]
#' @return A character scalar naming the default trigger.
#' @examples
#' default_trigger()
#' # See ?triggers for more examples.
default_trigger <- function(){
  "any"
}

triggers_with_command <- function(){
  c("any", "command")
}

triggers_with_depends <- function(){
  c("any", "depends")
}

triggers_with_file <- function(){
  c("any", "file")
}

get_trigger <- function(target, config){
  plan <- config$plan
  if (!(target %in% plan$target)){
    return("any")
  }
  drake_plan_override(
    target = target,
    field = "trigger",
    config = config
  )
}

assert_legal_triggers <- function(x){
  x <- setdiff(x, triggers())
  if (!length(x)){
    return(invisible())
  }
  stop(
    "Illegal triggers found. See triggers() for the legal ones. Illegal:\n",
    multiline_message(x),
    call. = FALSE
  )
}

command_trigger <- function(target, meta, config){
  stopifnot(!is.null(meta$command))
  command <- get_from_subspace(
    key = target,
    subspace = "command",
    namespace = "meta",
    cache = config$cache
  )
  !identical(command, meta$command)
}

depends_trigger <- function(target, meta, config){
  stopifnot(!is.null(meta$depends))
  depends <- get_from_subspace(
    key = target,
    subspace = "depends",
    namespace = "meta",
    cache = config$cache
  )
  !identical(depends, meta$depends)
}

file_trigger <- function(target, meta, config){
  stopifnot(!is.null(meta$file))
  if (!is_file(target)){
    return(FALSE)
  }
  if (!file.exists(drake_unquote(target))){
    return(TRUE)
  }
  tryCatch(
    !identical(
      config$cache$get(target, namespace = "kernels"),
      meta$file
    ),
    error = error_false
  )
}

should_build <- function(target, meta_list, config){
  if (meta_list[[target]]$imported) {
    return(TRUE)
  }
  should_build_target(
    target = target,
    meta = meta_list[[target]],
    config = config
  )
}

should_build_target <- function(target, meta, config){
  if (meta$missing){
    return(TRUE)
  }
  trigger <- get_trigger(target = target, config = config)
  if (trigger == "always"){
    return(TRUE)
  }
  do_build <- FALSE
  if (trigger %in% triggers_with_command()){
    do_build <- do_build ||
      command_trigger(target = target, meta = meta, config = config)
  }
  if (trigger %in% triggers_with_depends()){
    do_build <- do_build ||
      depends_trigger(target = target, meta = meta, config = config)
  }
  if (trigger %in% triggers_with_file()){
    do_build <- do_build ||
      file_trigger(target = target, meta = meta, config = config)
  }
  do_build
}

using_default_triggers <- function(config){
  default_plan_triggers <-
    is.null(config$plan[["trigger"]]) ||
    all(config$plan[["trigger"]] == default_trigger())
  default_plan_triggers && config$trigger == default_trigger()
}
