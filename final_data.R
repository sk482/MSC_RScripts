require(reshape2)
require(raster)
require(grid)
require(rgdal)
require(ggplot2)
require(fitdistrplus)
require(MASS)
require(PearsonDS)

#####Climate Data#####
climate.path <- "/Users/Simon/Studium/MSC/Masterarbeit/data/climate/BOM/"

#prec newhaven, tem Yuendumu
prec <- read.csv(paste0(climate.path, "IDCJAC0009_015611_1800_Data.csv"))
tem <- read.csv(paste0(climate.path, "IDCJAC0010_015528_1800_Data.csv"))
enso <- read.csv(paste0(climate.path, "southern_oscillation_index_1960_2015.csv"))

#aggregate prec data by year (annual rainfall sum)
prec.stats <- aggregate(prec$Rainfall.amount..millimetres., by = list(prec$Year), FUN = sum, na.rm = T)
tem.stats <- aggregate(tem$Maximum.temperature..Degree.C., by = list(tem$Year), FUN =  function(x){length(na.omit(x[x > 41]))})
enso.stats <- data.frame("year" = enso$Year, "mean_enso_index" = rowMeans(enso[,2:13]))
clim.stats <- merge(prec.stats, enso.stats, by.x = "Group.1", by.y = "year")
clim.stats <- merge(clim.stats, tem.stats, by.x = "Group.1", by.y = "Group.1")

#Calculate cumulative prec
clim.stats$yycumu <- NA
for (i in 3:51){
  clim.stats$yycumu[i] <-  clim.stats$x.x[i] + clim.stats$x.x[i-1] + clim.stats$x.x[i-2]
}
names(clim.stats) <- c("year", "prec", "enso_ind", "tem", "yycumu")

#####Fire Data#####
path.shp <- "/Users/Simon/Studium/MSC/Masterarbeit/data/fire/fire_data_reprojected_1970-2015"
files.shp <- list.files(path.shp, pattern = "*.shp$")

# read fire data
fs.shp.repr <- list()
for (i in 1:length(files)){
  tem <- readOGR(path.shp, substr(files[i], 1, 9))
  names(tem)[1] <- c("OBJECTID")
  fs.shp.repr[[i]] <- tem
  }

#Get fire sizes, calender year and number of fires from fire scar shapefiles
all <- data.frame("area" = fs.shp.repr[[1]]@data$Shape_Area, "year" = fs.shp.repr[[1]]@data$CalanderYe, "no_of_fires" = length(fs.shp.repr[[1]]@data$OBJECTID))
for (i in 2:length(files)){
  allnext <- data.frame("area" = fs.shp.repr[[i]]@data$Shape_Area, "year" = fs.shp.repr[[i]]@data$CalanderYe, "no_of_fires" = length(fs.shp.repr[[i]]@data$OBJECTID))
  all <- rbind(all, allnext)
  print(i)
}

#attach prec and tem data
pos <- match(all$year, clim.stats$year)
all$cumu_prec <- clim.stats$yycumu[pos]
all$tem <- clim.stats$tem[pos]

#LOAD TSF DATA
path.tsf <- "/Users/Simon/Studium/MSC/Masterarbeit/data/fire/tsf rasterized 1970-2015"
tsf.ts <- stack()
files <- list.files(path.tsf, pattern = "*.asc$")
n <- substr(files,5,9)
for (i in 1:length(files)){
  r.tsf <- raster(paste(path.tsf, files[i], sep = "/"))
  r.tsf@data@names <- paste0("tsf_", n[i])
  tsf.ts <- stack(tsf.ts, r.tsf)
}

######################################################
###PREC VS TOTAL AREA BURNED
######################################################
rm(year, tem)
detach(prec.stats)
detach(all)
attach(all)

wide_area <- 5503.63

total <- round((tapply(area, year, function(x) sum(x)))/wide_area * 100, digits = 3)
cumu <- tapply(cumu_prec, year, function(x) unique(x))

#MODEL
mod_total <- lm(log(total) ~ cumu)
summary(mod_total)
  
######################################################
####PREC VS FIRE SIZES####
######################################################
detach(all)
detach(clim.stats)
rm(year, tem)
attach(all)

#Subsets of years iwth sufficient data
s <- tapply(area, year, FUN = length)
subyrs <- c(1976, 1982,1983, 1984, 2000:2005, 2008:2012)
area.subs <- area[which(year%in%subyrs)]
years.subs <- year[which(year%in%subyrs)]
precan.subs <- unique(prec[which(year%in%subyrs)])
cumu2.subs <- unique(cumuyy[which(year%in%subyrs)])
cumu3.subs <- unique(cumuyyy[which(year%in%subyrs)])

#PEARSON
#Extract person moments
MM <-tapply(area.subs, years.subs, function(x) empMoments(x))

#Analyse pearson moments for correlation with prec
MMs <- matrix(nrow = length(MM), ncol = 4)
for (i in 1:length(MM)){
  MMs[i,1] <- MM[[i]][[1]]
  MMs[i,2] <- MM[[i]][[2]]
  MMs[i,3] <- MM[[i]][[3]]
  MMs[i,4] <- MM[[i]][[4]]
}

summary(lm(cumu3.subs ~ MMs[,1]))
summary(lm(cumu3.subs ~ MMs[,2]))
summary(lm(cumu3.subs ~ MMs[,3]))
summary(lm(cumu3.subs ~ MMs[,4]))



#LOGNORM

#unfitted lnorm pars
lnscales <- tapply(area.subs, years.subs, function(x) lnscale(x))
lnmeans <- tapply(area.subs, years.subs, function(x) lnmean(x))

scales <- tapply(area.subs, years.subs, function(x) lnscale(x))
locs <- tapply(area.subs, years.subs, function(x) lnmean(x))

locs_mod1 <- lm(locs ~ cumu3.subs)
locs_mod2 <- lm(locs ~ sqrt(cumu3.subs))
scales_mod1 <- lm(scales ~ cumu3.subs)
scales_mod2 <- lm(scales ~ sqrt(cumu3.subs))
#fitted lnorm pars
lnparsfitted <- tapply(area.subs, years.subs, function(x) fitdist(x, "lnorm")$estimate)

#NORM WITH LOGS
#unfitted norm pars
meanlog <- tapply(log(area.subs), years.subs, mean)
sdlog <- tapply(log(area.subs), years.subs, sd)

summary(lm(meanlog ~ cumu3.subs))
summary(lm(sdlog ~ cumu3.subs))

# #fitted norm pars truncated
# norm.trunc <- matrix(ncol = 4, nrow = 17)
# j <- tapply(area.subs, years.subs)
# minmax <- tapply(log(area.subs), years.subs, function(x) c(min(x), max(x)))
# for (i in 1:length(minmax)){
#   temp <- fitdistr(log(area.subs[which(j == i)]), "normal",  lower = minmax[[i]][1], upper = minmax[[i]][2], method = "mle")
#   estimate <- temp$estimate
#   loglik <- temp$loglik
#   norm.trunc[i,] <- c(unique(years.subs)[i], estimate[1], estimate[2], loglik)
# }

#summary(lm(norm.trunc[,2] ~ cumu.subs))
#summary(lm(norm.trunc[,3] ~ cumu.subs))


#calculate loglikelihood for each dist
fun_pears<- tapply(area.subs, years.subs, function(x) pearsFUN(x))
ll_pears<- tapply(area.subs, years.subs, function(x) loglikpears(x))
ll_gamma <- tapply(area.subs, years.subs, function(x) logLik(fitdist(x, "gamma", start=list(shape = 1, rate = 0.1),lower=0.1)))
ll_lnorm_fit <- tapply(area.subs, years.subs, function(x) logLik(fitdist(x, "lnorm")))
ll_lnorm_unfit <- numeric()
for (i in 1:length(lnscales)){
  t <- which(years.subs == unique(years.subs)[i])
  ll_lnorm_unfit[i] <- sum(log(dlnorm(area.subs[t], meanlog=lnmeans[[i]], sdlog=lnscales[[i]])))
}


#it seems like fitted preason or fitted log normal are best. Since fitted lognormal means that the function parameters are likelihood maximised, we can't calculate parameters from empiric mean and sd and have to correlate MLE with prec
plot(Lnorm)
points(Lnorm_trunc, col = "red")
sum(Lnorm)
sum(Lnorm_trunc)
lnormfuncs <- tapply(area.subs, years.subs, function(x) fitdistr(x, "lognormal"))
meanlogs <- vector()
sdlogs <- vector()
for (i in 1:length(lnormfuncs)){
  meanlogs[i] <- lnormfuncs[[i]]$estimate[1]
  sdlogs[i] <- lnormfuncs[[i]]$estimate[2]
}

plot(meanlogs,sdlogs)
mean(meanlogs)
summary(lm(meanlogs~cumu))
plot(cumu, meanlogs)
plot(cumu, sdlogs)

require(lattice)
attach(all)
densityplot(~log(area),groups = year,
            plot.points = FALSE, ref = TRUE, 
            auto.key = list(space = "right"), ylim = c(0,0.7), xlim = c(-10, 10))

densityplot(~log(fires$fire_achieved),groups = fires$yr,
            plot.points = FALSE, ref = TRUE, 
            auto.key = list(space = "right"), ylim = c(0,0.7), xlim = c(-10, 10))



t.test(log(fires$fire_achieved), log(all$area))
length(fires$fire_achieved)/75
length(all$area)/54

boxplot(log(area))
mean(all$area)
mean(fires$fire_achieved)

