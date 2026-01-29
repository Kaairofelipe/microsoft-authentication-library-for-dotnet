using Xunit;
using System;
using System.IO;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;

namespace Microsoft.Identity.Client.Tests.Security
{
    /// <summary>
    /// Security Validation Tests - Microsoft Security Baseline Compliance
    /// 
    /// Padrão: NIST Cybersecurity Framework + Microsoft Security Baseline
    /// Objetivo: Garantir que o código segue práticas de segurança oficiais
    /// </summary>
    public class SecurityValidationTests
    {
        private readonly string _projectRoot = FindProjectRoot();
        
        // ====================================================================
        // SETUP
        // ====================================================================
        
        private static string FindProjectRoot()
        {
            var current = Directory.GetCurrentDirectory();
            while (!File.Exists(Path.Combine(current, "Directory.Build.props")))
            {
                current = Directory.GetParent(current)?.FullName;
                if (current == null) throw new InvalidOperationException("Project root not found");
            }
            return current;
        }
        
        // ====================================================================
        // TESTES: CONFIGURAÇÃO
        // ====================================================================
        
        [Fact]
        [Trait("Category", "Security")]
        [Trait("Standard", "Microsoft Security Baseline")]
        public void DotenvFileNotInGit()
        {
            // Verificar que .env não está commitado
            var gitignorePath = Path.Combine(_projectRoot, ".gitignore");
            Assert.True(File.Exists(gitignorePath), ".gitignore deve existir");
            
            var gitignoreContent = File.ReadAllText(gitignorePath);
            Assert.Contains(".env", gitignoreContent, StringComparison.OrdinalIgnoreCase);
        }
        
        [Fact]
        [Trait("Category", "Security")]
        [Trait("Standard", "Microsoft Security Baseline")]
        public void EnvExampleNoSecretsExposed()
        {
            // .env.example não deve ter valores reais de secrets
            var envExamplePath = Path.Combine(_projectRoot, ".env.example");
            if (!File.Exists(envExamplePath)) return;
            
            var content = File.ReadAllText(envExamplePath);
            
            // Padrões não permitidos (valores reais)
            var forbiddenPatterns = new[]
            {
                @"password=[a-zA-Z0-9!@#$%^&*]{8,}",
                @"api_key=[a-zA-Z0-9_-]{32,}",
                @"secret=[a-zA-Z0-9_-]{32,}",
            };
            
            foreach (var pattern in forbiddenPatterns)
            {
                var matches = Regex.Matches(content, pattern);
                Assert.Empty(matches);
            }
        }
        
        // ====================================================================
        // TESTES: CÓDIGO-FONTE
        // ====================================================================
        
        [Fact]
        [Trait("Category", "Security")]
        [Trait("Standard", "NIST")]
        public void NoHardcodedPasswords()
        {
            // Procurar por hardcoded passwords no código
            var csFiles = Directory.GetFiles(
                Path.Combine(_projectRoot, "src"),
                "*.cs",
                SearchOption.AllDirectories);
            
            var issues = new List<string>();
            
            foreach (var file in csFiles)
            {
                var content = File.ReadAllText(file);
                
                // Padrões perigosos
                if (Regex.IsMatch(content, @"password\s*=\s*[""'](?!null|empty|example)", RegexOptions.IgnoreCase))
                {
                    issues.Add($"{file}: Possível hardcoded password");
                }
            }
            
            Assert.Empty(issues);
        }
        
        [Fact]
        [Trait("Category", "Security")]
        [Trait("Standard", "NIST")]
        public void NoHardcodedConnectionStrings()
        {
            // Procurar por hardcoded connection strings
            var csFiles = Directory.GetFiles(
                Path.Combine(_projectRoot, "src"),
                "*.cs",
                SearchOption.AllDirectories);
            
            var issues = new List<string>();
            
            foreach (var file in csFiles)
            {
                var content = File.ReadAllText(file);
                
                // Padrões perigosos (excepto comentários e exemplos)
                if (Regex.IsMatch(content, @"Server=.*password", RegexOptions.IgnoreCase))
                {
                    if (!content.Contains("example", StringComparison.OrdinalIgnoreCase))
                    {
                        issues.Add($"{file}: Possível hardcoded connection string");
                    }
                }
            }
            
            Assert.Empty(issues);
        }
        
        [Fact]
        [Trait("Category", "Security")]
        [Trait("Standard", "Microsoft Security Baseline")]
        public void NoConsoleLoggingOfSecrets()
        {
            // Procurar por logging de secrets
            var csFiles = Directory.GetFiles(
                Path.Combine(_projectRoot, "src"),
                "*.cs",
                SearchOption.AllDirectories);
            
            var issues = new List<string>();
            
            foreach (var file in csFiles)
            {
                var content = File.ReadAllText(file);
                
                // Padrões perigosos
                if (Regex.IsMatch(content, @"Console\.WriteLine.*(?:password|secret|token)", RegexOptions.IgnoreCase))
                {
                    issues.Add($"{file}: Possível console logging de secret");
                }
            }
            
            Assert.Empty(issues);
        }
        
        // ====================================================================
        // TESTES: DEPENDÊNCIAS
        // ====================================================================
        
        [Fact]
        [Trait("Category", "Security")]
        [Trait("Standard", "Microsoft Security Baseline")]
        public void NoDangerousDependencies()
        {
            // Packages conhecidos como perigosos
            var dangerousPackages = new[]
            {
                "System.Net.Http.WinHttpHandler", // Obsoleto
                "JsonWebToken",                    // Conflita com JWT
            };
            
            var propsFile = Path.Combine(_projectRoot, "Directory.Packages.props");
            Assert.True(File.Exists(propsFile), "Directory.Packages.props deve existir");
            
            var content = File.ReadAllText(propsFile);
            
            foreach (var package in dangerousPackages)
            {
                Assert.DoesNotContain(package, content);
            }
        }
        
        // ====================================================================
        // TESTES: DOCUMENTAÇÃO
        // ====================================================================
        
        [Fact]
        [Trait("Category", "Security")]
        [Trait("Standard", "NIST")]
        public void NoSecretsInDocumentation()
        {
            // Procurar por secrets em markdown
            var mdFiles = Directory.GetFiles(_projectRoot, "*.md", SearchOption.TopDirectoryOnly);
            
            var issues = new List<string>();
            
            foreach (var file in mdFiles)
            {
                var content = File.ReadAllText(file);
                
                // Padrões perigosos (mas permitir examples e fake)
                var lines = content.Split('\n');
                for (int i = 0; i < lines.Length; i++)
                {
                    var line = lines[i];
                    
                    if (Regex.IsMatch(line, @"password.*=.*[a-zA-Z0-9!@#$%^&*]{8,}", RegexOptions.IgnoreCase))
                    {
                        if (!line.Contains("example", StringComparison.OrdinalIgnoreCase) &&
                            !line.Contains("fake", StringComparison.OrdinalIgnoreCase))
                        {
                            issues.Add($"{Path.GetFileName(file)}:{i + 1}: Possível secret exposto");
                        }
                    }
                }
            }
            
            Assert.Empty(issues);
        }
        
        // ====================================================================
        // TESTES: DOCKER
        // ====================================================================
        
        [Fact]
        [Trait("Category", "Security")]
        [Trait("Standard", "Microsoft Security Baseline")]
        public void DockerfileHasNonRootUser()
        {
            var dockerfilePath = Path.Combine(_projectRoot, "Dockerfile.prod");
            if (!File.Exists(dockerfilePath)) return;
            
            var content = File.ReadAllText(dockerfilePath);
            
            // Deve ter USER configurado
            Assert.Matches(@"^USER\s+", content, RegexOptions.Multiline);
            
            // Não deve ser root
            Assert.DoesNotMatch(@"^USER\s+root\s*$", content, RegexOptions.Multiline);
        }
        
        [Fact]
        [Trait("Category", "Security")]
        [Trait("Standard", "Microsoft Security Baseline")]
        public void DockerfileNoHardcodedSecrets()
        {
            var dockerfilePath = Path.Combine(_projectRoot, "Dockerfile.prod");
            if (!File.Exists(dockerfilePath)) return;
            
            var content = File.ReadAllText(dockerfilePath);
            
            // Padrões perigosos (mas permitir variáveis de ambiente)
            var matches = Regex.Matches(content, @"(password|secret|token)\s*=\s*[^$]", RegexOptions.IgnoreCase);
            
            foreach (Match match in matches)
            {
                // Permitir se começar com ${
                if (!content.Substring(Math.Max(0, match.Index - 2), 2).Contains("${"))
                {
                    Assert.True(false, $"Encontrado secret hardcoded em Dockerfile: {match.Value}");
                }
            }
        }
        
        [Fact]
        [Trait("Category", "Security")]
        [Trait("Standard", "Microsoft Security Baseline")]
        public void DockerComposeNoHardcodedSecrets()
        {
            var composePath = Path.Combine(_projectRoot, "docker-compose.prod.yml");
            if (!File.Exists(composePath)) return;
            
            var content = File.ReadAllText(composePath);
            
            // Padrões perigosos (mas permitir variáveis de ambiente)
            var lines = content.Split('\n');
            
            foreach (var line in lines)
            {
                if (line.Contains("password:") && !line.Contains("${"))
                {
                    Assert.True(false, $"Encontrado secret hardcoded em docker-compose: {line}");
                }
            }
        }
        
        // ====================================================================
        // TESTES: COMPLIANCE
        // ====================================================================
        
        [Fact]
        [Trait("Category", "Compliance")]
        [Trait("Standard", "GDPR")]
        public void GDPRComplianceDocumentation()
        {
            // Deve ter documentação de compliance
            var docs = new[]
            {
                "AUDITORIA_SEGURANCA.md",
                "GUIA_OTIMIZACAO_SEGURANCA.md",
                "MONITORAMENTO_ALERTAS.md"
            };
            
            foreach (var doc in docs)
            {
                var path = Path.Combine(_projectRoot, doc);
                Assert.True(File.Exists(path), $"Documentação de compliance não encontrada: {doc}");
            }
        }
        
        [Fact]
        [Trait("Category", "Compliance")]
        [Trait("Standard", "Microsoft Security Baseline")]
        public void SecurityBaselineDocumentation()
        {
            var path = Path.Combine(_projectRoot, "GUIA_OTIMIZACAO_SEGURANCA.md");
            Assert.True(File.Exists(path), "Guia de otimização de segurança não encontrado");
            
            var content = File.ReadAllText(path);
            Assert.Contains("Docker", content);
            Assert.Contains("Security", content);
            Assert.Contains("Dockerfile", content);
        }
    }
}
