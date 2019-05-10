classdef nhgpmixturesolver < matlab.mixin.Copyable
    
    properties
        prior nhgpmixtureprior
    end
    
    methods
        function solver = nhgpmixturesolver(prior)
            solver.prior = prior;
        end
        
        function [nhgpmixture_MAP, score] = compute_EM_estimate(obj, data, algorithm, J, initial_nhgpmixture)
            if nargin > 4
                estimate_mixture = initial_nhgpmixture;
                x_timegrid = initial_nhgpmixture.gp_component.x_timegrid;
            else
                x_timegrid = obj.prior.m_gpprior.x_timegrid;
                % broken, must be random mixture
                estimate_mixture = nhgpmodel(x_timegrid, mean(data,2), log(1.0)*ones(size(x_timegrid)), log(0.01)*ones(size(x_timegrid)), log(1.0)*ones(size(x_timegrid)));
            end
            
            if nargin < 4
                J = 10000;
            end
            
            assert(length(x_timegrid) == size(data,1), 'invalid shape data matrix');
            
            switch algorithm
               case 'Kimura'
                  [nhgpmixture_MAP, score] = compute_EM_estimate_Kimura(obj, data, J, estimate_mixture);
               case 'GEM'
                  [nhgpmixture_MAP, score] = compute_EM_estimate_GEM(obj, data, J, estimate_mixture);
               otherwise
                  error('invalid optimization algorithm');
            end
        end
        
        function initial_nhgpmixture = initialization(obj, method, data, n)
            switch method
               case 'prior'
                  initial_nhgpmixture = obj.prior.random_nhgpmixture();
               case 'subsetfit'
                   initial_nhgpmixture = obj.initialization_subsetfit(data, n);
               otherwise
                  error('invalid initialization method');
            end
        end
        
        function initial_nhgpmixture = initialization_subsetfit(obj, data, n)
            solver = nhgpsolver(obj.prior.G0);
            solver.default_optimality_tol = 0.1;
            algorithm = 'quasi-newton';
            proportion = ones(1, obj.prior.K)./obj.prior.K;
            gp_component_array = {};
            parfor k = 1:obj.prior.K
                k
                idx = randperm(size(data,2), n);
                gp_component_array{k} = solver.compute_MAP_estimate(data(:,idx), algorithm, 10);
                gp_component_array{k} = solver.compute_MAP_estimate(data(:,idx), algorithm, 10, gp_component_array{k});
                gp_component_array{k} = solver.compute_MAP_estimate(data(:,idx), algorithm, 10, gp_component_array{k});
                gp_component_array{k} = solver.compute_MAP_estimate(data(:,idx), algorithm, 10, gp_component_array{k});
                gp_component_array{k} = solver.compute_MAP_estimate(data(:,idx), algorithm, 500, gp_component_array{k});
                gp_component_array{k} = solver.compute_MAP_estimate(data(:,idx), algorithm, 500, gp_component_array{k});
                
%                 figure(90999); 
%                 clf;
%                 gp_component_array{k}.show();
%                 hold on;
%                 plot(solver.prior.m_gpprior.x_timegrid, data(:,idx));
            end
            gp_component = gp_component_array{1};
            for k = 1:obj.prior.K
                gp_component(k) = copy(gp_component_array{k});
            end
            initial_nhgpmixture = nhgpmixture(proportion, gp_component);
        end
        
        function [nhgpmixture_MAP, score] = compute_EM_estimate_GEM(obj, data, J, estimate_mixture)
            history = NaN(1,J);
            history(1) = estimate_mixture.logpdf(data) + obj.prior.logpdf(estimate_mixture);
            x_timegrid = obj.prior.G0.m_gpprior.x_timegrid;
            
            history_ARI = NaN(1,J);
            history_ARI(1) = 0.0;
            
            % temporary
            global gt_labels; 
            
            for j = 2:J
                estimate_mixture.reorder_components();
                
                % E-step
                E_MP = estimate_mixture.membership_logproba(data);
                PZ = exp(E_MP) ./ repmat(sum(exp(E_MP)),size(E_MP,1),1);
                
                % temporary
                [~, b] = max(PZ);
                history_ARI(j) = rand_index(gt_labels,b,'adjusted'); 
                figure(991);
                plot(history_ARI);
                title('adjusted rand index');
                
                figure(19);
                imagesc(exp(E_MP));
                
                figure(3);
                clf;
                nb_plot = ceil(sqrt(sum(any(PZ > 0.50,2))));
                i_plot = 1;
                for k = 1:obj.prior.K
                    idx = PZ(k,:) > 0.50;
                    if any(idx)
                        subplot(nb_plot, nb_plot, i_plot);
                        estimate_mixture.gp_component(k).show();
                        hold on;
                        plot(x_timegrid, data(:, idx));
                        hold off;
                        i_plot = i_plot + 1;
                    end
                end
                drawnow;
                
                % M-step proportions
                v = zeros(1,obj.prior.K);
                S = sum(exp(E_MP),2);
                for k = 1:obj.prior.K-1
                    v(k) = S(k) / (S(k) + obj.prior.alpha - 1 + sum(S(k+1:end)));
                end
                v(obj.prior.K) = 1;
                vinv = 1 - v;
                estimate_mixture.proportion = arrayfun(@(n) v(n)*prod(vinv(1:n-1)), 1:obj.prior.K) + 0.00001;
                estimate_mixture.proportion = estimate_mixture.proportion ./ sum(estimate_mixture.proportion);

                % M-step theta
                solver = nhgpsolver(obj.prior.G0);
                nb_gradient_step_on_theta = 1000;
                returned_estimate_mixture = cell(1,obj.prior.K);  
                for k=1:obj.prior.K
                    data_importance = PZ(k,:);
                    idx = find(data_importance > 0.01);
                    data_importance = data_importance(idx);
                    data_subset = data(:,idx);
                    if ~isempty(idx)
                        theta0 = estimate_mixture.gp_component(k).theta;
                        score0 = -dot(estimate_mixture.gp_component(k).logpdf(data_subset), data_importance) - obj.prior.G0.logpdf(estimate_mixture.gp_component(k).theta); 
                        if length(idx) > 30
                            idx_ = randperm(length(idx), 30);
                            returned_estimate_mixture{k} = solver.compute_MAP_estimate(data_subset(:,idx_), 'quasi-newton', nb_gradient_step_on_theta, estimate_mixture.gp_component(k), data_importance(idx_), 0.2);
                            score1 = -dot(returned_estimate_mixture{k}.logpdf(data_subset), data_importance) - obj.prior.G0.logpdf(returned_estimate_mixture{k}.theta);
                            if score0 < score1
                                returned_estimate_mixture{k}.theta = theta0;
                            end
                        else
                            returned_estimate_mixture{k} = solver.compute_MAP_estimate(data_subset, 'quasi-newton', nb_gradient_step_on_theta, estimate_mixture.gp_component(k), data_importance, 0.2);
                        end
                    else
                        if rand < 0.5
                            nb_seed = 5;
                            data_importance = ones(1,nb_seed);
                            idx = randperm(size(data,2), nb_seed);
                            data_subset = data(:,idx);
                            new_nhgp = nhgpmodel(x_timegrid, movmean(mean(data_subset,2),5), log(1.0)*ones(size(x_timegrid)), log(0.01)*ones(size(x_timegrid)), log(1.0)*ones(size(x_timegrid)));
                            solver.compute_MAP_estimate(data_subset, 'quasi-newton', nb_gradient_step_on_theta, new_nhgp, data_importance);
                            returned_estimate_mixture{k} = solver.compute_MAP_estimate(data_subset, 'quasi-newton', nb_gradient_step_on_theta, new_nhgp, data_importance, 0.005);
                        else
                            returned_estimate_mixture{k} = obj.prior.G0.random_nhgp();
                        end
                    end
                end
                for k=1:obj.prior.K                                             
                    estimate_mixture.gp_component(k) = returned_estimate_mixture{k};
                end  
                history(j) = estimate_mixture.logpdf(data) + obj.prior.logpdf(estimate_mixture);
                figure(99);
                semilogy(history);

                E_MP = estimate_mixture.membership_logproba(data);
                PZ = exp(E_MP) ./ repmat(sum(exp(E_MP)),size(E_MP,1),1);
                
                figure(3);
                clf;
                nb_plot = ceil(sqrt(sum(any(PZ > 0.50,2))));
                i_plot = 1;
                for k = 1:obj.prior.K
                    idx = PZ(k,:) > 0.50;
                    if any(idx)
                        subplot(nb_plot, nb_plot, i_plot);
                        estimate_mixture.gp_component(k).show();
                        hold on;
                        plot(x_timegrid, data(:, idx));
                        hold off;
                        i_plot = i_plot + 1;
                    end
                end
                
                drawnow;
            end
            nhgpmixture_MAP = estimate_mixture;
            score = NaN;
        end
        
        function [nhgpmixture_MAP, score] = compute_EM_estimate_Kimura(obj, data, J, estimate_mixture)
            history = NaN(1,J);
            history(1) = estimate_mixture.logpdf(data) + obj.prior.logpdf(estimate_mixture);
            x_timegrid = obj.prior.G0.m_gpprior.x_timegrid;
            
            history_ARI = NaN(1,J);
            history_ARI(1) = 0.0;
            
            
            
            % temporary
            global gt_labels; 
            
            for j = 2:J
                estimate_mixture.reorder_components();
                
                % E-step
                E_MP = estimate_mixture.membership_logproba(data);
                PZ = exp(E_MP) ./ repmat(sum(exp(E_MP)),size(E_MP,1),1);
                
                % temporary
                [~, b] = max(PZ);
                history_ARI(j) = rand_index(gt_labels,b,'adjusted'); 
                figure(991);
                plot(history_ARI);
                title('adjusted rand index');
                
                figure(19);
                imagesc(exp(E_MP));
                
                figure(3);
                clf;
                nb_plot = ceil(sqrt(sum(any(PZ > 0.50,2))));
                i_plot = 1;
                for k = 1:obj.prior.K
                    idx = PZ(k,:) > 0.50;
                    if any(idx)
                        subplot(nb_plot, nb_plot, i_plot);
                        estimate_mixture.gp_component(k).show();
                        hold on;
                        plot(x_timegrid, data(:, idx));
                        hold off;
                        i_plot = i_plot + 1;
                    end
                end
                drawnow;
                
                % M-step proportions
                v = zeros(1,obj.prior.K);
                S = sum(exp(E_MP),2);
                for k = 1:obj.prior.K-1
                    v(k) = S(k) / (S(k) + obj.prior.alpha - 1 + sum(S(k+1:end)));
                end
                v(obj.prior.K) = 1;
                vinv = 1 - v;
                estimate_mixture.proportion = arrayfun(@(n) v(n)*prod(vinv(1:n-1)), 1:obj.prior.K) + 0.00001;
                estimate_mixture.proportion = estimate_mixture.proportion ./ sum(estimate_mixture.proportion);

                % M-step theta
                solver = nhgpsolver(obj.prior.G0);
                solver.verbose_level='iter-detailed';
                nb_gradient_step_on_theta = 50;
                returned_estimate_mixture = cell(1,obj.prior.K);  
                for k=1:obj.prior.K
                    data_importance = PZ(k,:);
                    idx = find(data_importance > 0.01);
                    data_importance = data_importance(idx);
                    data_subset = data(:,idx);
                    if ~isempty(idx)
                        returned_estimate_mixture{k} = solver.compute_MAP_estimate(data_subset, 'quasi-newton', nb_gradient_step_on_theta, estimate_mixture.gp_component(k), data_importance, 0.2);
                    else
                        if rand < 0.5
                            nb_seed = 5;
                            data_importance = ones(1,nb_seed);
                            idx = randperm(size(data,2), nb_seed);
                            data_subset = data(:,idx);
                            new_nhgp = nhgpmodel(x_timegrid, movmean(mean(data_subset,2),5), log(1.0)*ones(size(x_timegrid)), log(0.01)*ones(size(x_timegrid)), log(1.0)*ones(size(x_timegrid)));
                            solver.compute_MAP_estimate(data_subset, 'quasi-newton', nb_gradient_step_on_theta, new_nhgp, data_importance);
                            returned_estimate_mixture{k} = solver.compute_MAP_estimate(data_subset, 'quasi-newton', nb_gradient_step_on_theta*10, new_nhgp, data_importance, 0.005);
                        else
                            returned_estimate_mixture{k} = obj.prior.G0.random_nhgp();
                        end
                    end
                end
                for k=1:obj.prior.K                                             
                    estimate_mixture.gp_component(k) = returned_estimate_mixture{k};
                end  
                history(j) = estimate_mixture.logpdf(data) + obj.prior.logpdf(estimate_mixture);
                figure(99);
                semilogy(history);

                E_MP = estimate_mixture.membership_logproba(data);
                PZ = exp(E_MP) ./ repmat(sum(exp(E_MP)),size(E_MP,1),1);
                
                figure(3);
                clf;
                nb_plot = ceil(sqrt(sum(any(PZ > 0.50,2))));
                i_plot = 1;
                for k = 1:obj.prior.K
                    idx = PZ(k,:) > 0.50;
                    if any(idx)
                        subplot(nb_plot, nb_plot, i_plot);
                        estimate_mixture.gp_component(k).show();
                        hold on;
                        plot(x_timegrid, data(:, idx));
                        hold off;
                        i_plot = i_plot + 1;
                    end
                end
                
                drawnow;
            end
            nhgpmixture_MAP = estimate_mixture;
            score = NaN;
        end
    end
end
