<?php

namespace App\Entity;

use ApiPlatform\Metadata\GraphQl\DeleteMutation;
use ApiPlatform\Metadata\GraphQl\Mutation;
use ApiPlatform\Metadata\GraphQl\Query;
use ApiPlatform\Metadata\GraphQl\QueryCollection;
use ApiPlatform\Metadata\ApiResource;
use App\Repository\TaskRepository;
use App\State\TaskCreateProcessor;
use Doctrine\ORM\Mapping as ORM;
use Symfony\Component\Serializer\Attribute\Groups;
use Symfony\Component\Uid\Uuid;
use Symfony\Component\Validator\Constraints as Assert;

/**
 * GraphQL-only resource: no REST operations are exposed, matching this
 * project's brief of "the API is GraphQL". Every operation is restricted to
 * the owning user, both by a `security` expression (single-item checks) and
 * by App\Doctrine\CurrentUserTaskExtension, which filters every underlying
 * Doctrine query (including collections, where a `security` expression alone
 * cannot scope individual rows).
 */
#[ORM\Entity(repositoryClass: TaskRepository::class)]
#[ApiResource(
    operations: [],
    graphQlOperations: [
        new Query(security: "is_granted('ROLE_USER') and (object === null or object.getOwner() == user)"),
        new QueryCollection(security: "is_granted('ROLE_USER')", paginationEnabled: false),
        new Mutation(name: 'create', security: "is_granted('ROLE_USER')", processor: TaskCreateProcessor::class),
        new Mutation(name: 'update', security: "is_granted('ROLE_USER') and (previous_object === null or previous_object.getOwner() == user)"),
        new DeleteMutation(name: 'delete', security: "is_granted('ROLE_USER') and (previous_object === null or previous_object.getOwner() == user)"),
    ],
    normalizationContext: ['groups' => ['task:read']],
    denormalizationContext: ['groups' => ['task:write']],
)]
class Task
{
    #[ORM\Id]
    #[ORM\Column(type: 'uuid', unique: true)]
    #[Groups(['task:read'])]
    private Uuid $id;

    #[ORM\Column(length: 255)]
    #[Groups(['task:read', 'task:write'])]
    #[Assert\NotBlank]
    #[Assert\Length(max: 255)]
    private string $title = '';

    #[ORM\Column]
    #[Groups(['task:read', 'task:write'])]
    private bool $done = false;

    #[ORM\Column]
    #[Groups(['task:read'])]
    private \DateTimeImmutable $createdAt;

    /**
     * Deliberately not in any serialization group: ownership can only be set
     * by TaskCreateProcessor from the authenticated user, never from client input.
     */
    #[ORM\ManyToOne(targetEntity: User::class)]
    #[ORM\JoinColumn(nullable: false, onDelete: 'CASCADE')]
    private User $owner;

    public function __construct()
    {
        $this->id = Uuid::v7();
        $this->createdAt = new \DateTimeImmutable();
    }

    public function getId(): Uuid
    {
        return $this->id;
    }

    public function getTitle(): string
    {
        return $this->title;
    }

    public function setTitle(string $title): static
    {
        $this->title = $title;

        return $this;
    }

    public function isDone(): bool
    {
        return $this->done;
    }

    public function setDone(bool $done): static
    {
        $this->done = $done;

        return $this;
    }

    public function getCreatedAt(): \DateTimeImmutable
    {
        return $this->createdAt;
    }

    public function getOwner(): User
    {
        return $this->owner;
    }

    public function setOwner(User $owner): static
    {
        $this->owner = $owner;

        return $this;
    }
}
