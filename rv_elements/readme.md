# Convert a State Vector to Keplerian Orbital Elements
## 程序说明
计算弧度没有确保输入的余弦值在$[-1,1]$范围内，可能导致由于浮点数精度导致的错误。
```cpp
cos_theta = std::max(-1.0, std::min(1.0, cos_theta));
```
## 公式
已知
$$
\begin{align}
\ddot{\vec{r}}&=-\frac{\mu}{r^3}\vec{r}\\
\vec{h}&=\vec{r}\times\dot{\vec{r}}\\
\ddot{\vec{r}}\times\vec{h}&=-\frac{\mu}{r^2}\vec{r}+\frac{\mu}{r}\dot{\vec{r}}\\
\dot{\vec{r}}\times\vec{h}&=\frac{\mu}{r}\vec{r}+\vec{B}\\
h^2&=\mu r+\vec{B}\cdot\vec{r}\\
\end{align}
$$
$$
\begin{equation}
r=\frac{h^2/\mu}{1+e\cos{f}}=\frac{p=a(1-e^2)}{1+e\cos{f}}
\end{equation}
$$
活力公式：
$$
\frac{1}{2}v^2-\frac{\mu}{r}=-\frac{\mu}{2a}
$$
升交点向量：
$$
\vec{\Omega}=(0,0,1)\times\vec{h}
$$
近地点向量：
$$
\vec{\omega}=\vec{B}=\mu\vec{e}
$$
$rv$转换轨道根数如下：
$$
\begin{align}
a&=-\mu/2/(v^2/2-\mu/r)\\
e&=\sqrt{1-h^2/(\mu a)}\\
\cos{i}&=\frac{\vec{h}\cdot(0,0,1)}{|\vec{h}|}\\
\cos{\Omega}&=\frac{\vec{\Omega}\cdot(1,0,0)}{|\vec{\Omega}|}\\
\cos{\omega}&=\frac{\vec{B}\cdot\vec{\Omega}}{|\vec{B}|\cdot|\vec{\Omega}|}\\
\cos{f}&=(h^2/\mu r-1)/e
\end{align}
$$