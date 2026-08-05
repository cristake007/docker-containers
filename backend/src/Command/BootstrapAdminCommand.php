<?php

namespace App\Command;

use App\Entity\User;
use App\Repository\UserRepository;
use Doctrine\ORM\EntityManagerInterface;
use Symfony\Component\Console\Attribute\AsCommand;
use Symfony\Component\Console\Command\Command;
use Symfony\Component\Console\Input\InputInterface;
use Symfony\Component\Console\Output\OutputInterface;
use Symfony\Component\Console\Style\SymfonyStyle;
use Symfony\Component\DependencyInjection\Attribute\Autowire;
use Symfony\Component\PasswordHasher\Hasher\UserPasswordHasherInterface;
use Symfony\Component\Validator\Constraints as Assert;
use Symfony\Component\Validator\Validator\ValidatorInterface;

/**
 * There is no self-registration in this application (see README): the only
 * account is a single admin, created or updated from ADMIN_EMAIL /
 * ADMIN_PASSWORD every time this command runs. Re-running it after changing
 * those values in the environment is how the admin credentials are rotated.
 *
 * Deliberately not run automatically by the container entrypoint, for the
 * same reason migrations aren't (see docker/backend/entrypoint.sh): it needs
 * the `user` table to already exist, and an explicit step avoids surprising
 * a fresh checkout with a silent write on every boot.
 */
#[AsCommand(
    name: 'app:bootstrap-admin',
    description: 'Creates or updates the single admin account from ADMIN_EMAIL / ADMIN_PASSWORD.',
)]
final class BootstrapAdminCommand extends Command
{
    private const string PLACEHOLDER_PASSWORD = 'dev-insecure-admin-password-do-not-use-in-prod';

    public function __construct(
        private readonly EntityManagerInterface $entityManager,
        private readonly UserRepository $userRepository,
        private readonly UserPasswordHasherInterface $passwordHasher,
        private readonly ValidatorInterface $validator,
        #[Autowire('%kernel.environment%')]
        private readonly string $environment,
        #[Autowire(env: 'ADMIN_EMAIL')]
        private readonly string $adminEmail,
        #[Autowire(env: 'ADMIN_PASSWORD')]
        private readonly string $adminPassword,
    ) {
        parent::__construct();
    }

    protected function execute(InputInterface $input, OutputInterface $output): int
    {
        $io = new SymfonyStyle($input, $output);

        // Canonicalized the same way User::setEmail expects (see its
        // docblock): lowercased and trimmed, so this is the one write path
        // that keeps email lookups case-insensitive end to end.
        $email = mb_strtolower(trim($this->adminEmail));
        $password = $this->adminPassword;

        if ('' === $email || '' === $password) {
            $io->error('ADMIN_EMAIL and ADMIN_PASSWORD must both be set (see .env).');

            return Command::FAILURE;
        }

        if ('prod' === $this->environment && $password === self::PLACEHOLDER_PASSWORD) {
            $io->error('ADMIN_PASSWORD still has its committed dev placeholder value. Set a real password (see .env).');

            return Command::FAILURE;
        }

        $violations = [
            ...iterator_to_array($this->validator->validate($email, [new Assert\NotBlank(), new Assert\Email()])),
            ...iterator_to_array($this->validator->validate($password, [new Assert\NotBlank(), new Assert\Length(min: 8, max: 4096)])),
        ];
        if (\count($violations) > 0) {
            foreach ($violations as $violation) {
                $io->error((string) $violation->getMessage());
            }

            return Command::FAILURE;
        }

        $user = $this->userRepository->findOneBy(['email' => $email]) ?? new User();
        $user->setEmail($email);
        $user->setRoles(['ROLE_ADMIN']);
        $user->setPassword($this->passwordHasher->hashPassword($user, $password));

        $this->entityManager->persist($user);
        $this->entityManager->flush();

        $io->success(\sprintf('Admin account for %s is ready.', $email));

        return Command::SUCCESS;
    }
}
