x_timegrid = linspace(-1,1,200);

hyper = make_hyper();

prior = nhgpprior(x_timegrid, ...
                  hyper.mu_m, hyper.G_m, hyper.L_m, ...
                  hyper.mu_loggamma, hyper.G_loggamma, hyper.L_loggamma, ...
                  hyper.mu_loglambda, hyper.G_loglambda, hyper.L_loglambda, ...
                  hyper.mu_logeta, hyper.G_logeta, hyper.L_logeta, ...
                  hyper.tol);

m = prior.m_random();
gamma = exp(prior.loggamma_random());
lambda = exp(prior.loglambda_random());
eta = exp(prior.logeta_random());

model = nhgpmodel(x_timegrid, m, gamma, lambda, eta);

F = model.random(5);

model.show();
hold on;
plot(x_timegrid, F);

model.logpdf(F)

