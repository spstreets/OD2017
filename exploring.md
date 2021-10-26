Exploring OD2017 data
================

I create this separated document to be the main reference on the
exploratory data analysis. The data set is at the trip level and I take
advantage of the survey design and use the expansion factor (for the
trips) in all the graphs and analysis here. The survey implies that
there are 4.20066610^{7} trips/day in the São Paulo Metro Region.

### Key variables

The data set contains a lot of socioeconomic variables. Since our
interest relies on trips, flows and mode choices, the analyses so far
are at the trip level. In this context, the variables that contain a the
modes used in each trip are the main ones (`modo1`, `modo2`, `modo3`,
and `modo4`). There is also the coordinates for each residence
(`co_dom_x` and `co_dom_y`) and workplaces (`co_tr1_x` and `co_tr1_y`),
and obviously the origin and destination zones and coordinates
(e.g. `zona_o`, `co_o_x`, `co_o_y`) and euclidean distance. As you can
see in the graph below, the vast majority of trips are made using just
one mode. I use the main mode used in the trip (`modoprin`) in the
remaining graphs.

![](exploring_files/figure-gfm/unnamed-chunk-2-1.png)<!-- -->

### Recategorisation of modes

I tried two different recategorisations (see code for the choices).The
first is based on the “vehicle” itself, and the other relies on the
“role” of the individual while in the trip.

![](exploring_files/figure-gfm/unnamed-chunk-3-1.png)<!-- -->

Now the A/B Streets classification (foot, bike, car, public transport
and other):

![](exploring_files/figure-gfm/unnamed-chunk-4-1.png)<!-- -->

Now the mode share by distance (using the first recategorisation). The
average trips’ distance is 5305.0981626.

    #> `summarise()` regrouping output by 'dist_bands' (override with `.groups` argument)

![](exploring_files/figure-gfm/unnamed-chunk-5-1.png)<!-- -->

    #> `summarise()` regrouping output by 'dist_bands' (override with `.groups` argument)

![](exploring_files/figure-gfm/unnamed-chunk-6-1.png)<!-- -->

    #> `summarise()` regrouping output by 'dist_bands' (override with `.groups` argument)

![](exploring_files/figure-gfm/unnamed-chunk-7-1.png)<!-- -->

### Basic temporal analysis

Distributions of trips in the day

![](exploring_files/figure-gfm/unnamed-chunk-9-1.png)<!-- -->

![](exploring_files/figure-gfm/unnamed-chunk-10-1.png)<!-- -->

### Basic geographic analysis (now with times )

Here I plot the main zones of origin and destination using the total
number of trips – always using the survey’s expansion factor. It is
interesting to note that there is no centrality pattern when we look at
the main Zones of Destination. Maybe we should restrict the analysis to
specific types of trips (e.g., commute strictly defined). I checked
these results with the official Tables and they are the same in terms of
the main zones of origin and destination.

Plotting the origin zones by time.

![](exploring_files/figure-gfm/unnamed-chunk-13-1.png)<!-- -->

Plotting the destination zones by time.

![](exploring_files/figure-gfm/unnamed-chunk-14-1.png)<!-- -->

Looking at the São Paulo City. First, the origins.

![](exploring_files/figure-gfm/unnamed-chunk-15-1.png)<!-- -->

Now, the destinations for São Paulo City.

![](exploring_files/figure-gfm/unnamed-chunk-16-1.png)<!-- -->

#### Distances by zone of residence

![](exploring_files/figure-gfm/unnamed-chunk-17-1.png)<!-- -->

#### Active travels and trip patterns

(I removed the previous visualizations since they were not saying
anything about the data.)

Walking and cycling are highly concentrated in few OD pairs (\>90% in
1,000 pairs for walking and \>90% in 500 pairs for cycling). Car trips
are more dispersed, we have \>90% of trips in 10,000 pairs.

Bike trips:

    #> Creating centroids representing desire line start and end points.

![](exploring_files/figure-gfm/unnamed-chunk-19-1.png)<!-- -->

Foot trips:

    #> Creating centroids representing desire line start and end points.

![](exploring_files/figure-gfm/unnamed-chunk-20-1.png)<!-- -->

Car trips, still too many lines (10,000) to account for \>92% of total
car trips.

    #> Creating centroids representing desire line start and end points.

![](exploring_files/figure-gfm/unnamed-chunk-21-1.png)<!-- -->

Using the first 5,000 OD pairs, we have \>78% of all car trips.

    #> Creating centroids representing desire line start and end points.

![](exploring_files/figure-gfm/unnamed-chunk-22-1.png)<!-- -->

Using the biggest 1,000 pairs, we have \>45% of all car trips.

    #> Creating centroids representing desire line start and end points.

![](exploring_files/figure-gfm/unnamed-chunk-23-1.png)<!-- -->

### Main routes by mode (takes a long time here) – rewriting this part.

### Plotting the routes

Load the routes I calculated.

something wrong here, check later…

### Infrastructure data (São Paulo municipality only)

obs.: very strange behavior here: st\_buffer + st\_make\_valid makes one
single polygon very small. without st\_buffer, R does not even plot – “C
stack usage too close to …”. These operations seems to be necessary in
the other geometries.

OD pairs that generate the most intensive usage of space (kms traveled
in the routes) have more area allocated to the transport mode (both foot
and car)

Very strong pattern here.

Some outliers in this graph, may be worth to check later…
