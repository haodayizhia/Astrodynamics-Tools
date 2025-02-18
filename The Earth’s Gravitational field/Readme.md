# The Earth’s Gravitational field

## Gravitational force

The Gravitational force between two particles with point mass $M$ at position $\mathbf{r}_0$ and $m$ at position $\mathbf{r}$ separated by a distance r is an attraction along a line join the particles:

$$
F=\left|\left|\mathbf{F}\right|\right|=G\frac{Mm}{r^2}
$$

$G$ is the universal gravitational constant: $G=6.673\times10^{-11}\mathrm{m}^3\mathrm{kg}^{-1}\mathrm{s}^{-2}$.

So, When considering the Earth as a point mass $M$ located at the origin, the gravitational force exerted on a point mass $m$ at a position vector $\mathbf{r}$ relative to the center of the Earth is given by:

$$
\mathbf{F}=m\mathbf{g}=-G\frac{Mm}{\left|\mathbf{r}\right|^3}\mathbf{r}
$$

We defined the vector $\mathbf{g}$ as the gravity field produced by a point mass $M$.

## Gravitational potential

Any mass $m$ in gravity field $\mathbf{g}$ has gravitational potential energy, the energy can be regarded as the work $W$ down on a mass $m$ by the gravitational force due to $M$ in moving from $\mathbf{r}$ to $\mathbf{r}\_{ref}$ where one often takes $\mathbf{r}_{ref}=\infty$. The gravitational potential $U$ is the potential energy in the field due to $M$ per unit mass.

$$
U=\int_\mathbf{r}^{\mathbf{r}\_{ref}}\mathbf{g}\cdot d\mathbf{r}=-\int_\mathbf{r}^{\mathbf{r}_{ref}}\frac{GM}{r^2}\hat{\mathbf{r}}\cdot d\mathbf{r}=-\int_r^\infty\frac{GM}{r^2}dr
=-\frac{GM}{r}
$$

> Gravitational potential can also be understood as the work done to move a unit point mass $m$ from the reference zero potential at $\mathbf{r}_{ref}$ to $\mathbf{r}$, overcoming the gravitational force.

$$
U=\int_{\mathbf{r}_{ref}}^\mathbf{r}-\mathbf{g}\cdot d\mathbf{r}=\int_{\mathbf{r}\_{ref}}^\mathbf{r}\frac{GM}{r^2}\hat{\mathbf{r}}\cdot d\mathbf{r}=\int_\infty^r\frac{GM}{r^2}dr
=-\frac{GM}{r}
$$

$$
\mathbf{g}=-\frac{GM}{r^2}\hat{\mathbf{r}}=
$$